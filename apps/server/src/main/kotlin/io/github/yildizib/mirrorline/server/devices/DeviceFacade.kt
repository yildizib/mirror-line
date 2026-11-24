package io.github.yildizib.mirrorline.server.devices

import io.github.yildizib.mirrorline.server.identity.AccountActionTokenRepository
import io.github.yildizib.mirrorline.server.identity.AccountFacade
import io.github.yildizib.mirrorline.server.identity.AccountFacade.Companion.encode
import io.github.yildizib.mirrorline.server.identity.AccountFacade.Companion.hash
import io.github.yildizib.mirrorline.server.identity.SessionRepository
import io.github.yildizib.mirrorline.server.shared.ApiException
import io.github.yildizib.mirrorline.server.shared.CorrelationIds
import io.github.yildizib.mirrorline.server.shared.FailureSecurityAuditService
import io.github.yildizib.mirrorline.server.shared.SecurityAuditPersistenceRepository
import io.github.yildizib.mirrorline.server.shared.protocolv1.CanonicalJson
import org.springframework.dao.DataAccessException
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.UUID

data class DeviceEnrollment(
    val enrollmentToken: String,
    val role: String,
    val platform: String,
    val appVersion: String,
    val displayName: String,
    val signingPublicKey: ByteArray,
    val encryptionPublicKey: ByteArray,
    val proofSignature: ByteArray,
)

data class DeviceEnrollmentResult(
    val userId: UUID,
    val deviceId: UUID,
    val keyVersion: Int,
    val accessToken: String,
    val refreshToken: String,
)

@Service
class DeviceFacade(
    private val actions: AccountActionTokenRepository,
    private val devices: DeviceAccountRepository,
    private val accountFacade: AccountFacade,
    private val sessions: SessionRepository,
    private val audit: SecurityAuditPersistenceRepository,
    private val failureAudit: FailureSecurityAuditService,
) {
    @Transactional
    fun enroll(input: DeviceEnrollment): DeviceEnrollmentResult {
        validateInput(input)
        val tokenHash = hash(input.enrollmentToken)
        val token =
            actions.findActive("DEVICE_ENROLLMENT", tokenHash)
                ?: registrationFailure(null, "AUTH_FORBIDDEN")
        if (!verifyProof(token.challenge!!, input)) registrationFailure(token.userId, "PAIRING_PROOF_INVALID")
        if (actions.consume("DEVICE_ENROLLMENT", tokenHash) == null) registrationFailure(token.userId, "AUTH_FORBIDDEN")
        try {
            val deviceId = devices.createActive(token.userId, input.role, input.platform, input.appVersion, input.displayName)
            val binding = hash(canonicalProofBytes(token.challenge, input))
            val fingerprint = encode(MessageDigest.getInstance("SHA-256").digest(input.signingPublicKey))
            devices.createActiveKeyVersionOne(
                token.userId,
                deviceId,
                input.signingPublicKey,
                input.encryptionPublicKey,
                binding,
                fingerprint,
            )
            val pair = accountFacade.createSession(token.userId, deviceId)
            accountFacade.recordDeviceBoundLogin(token.userId)
            audit.append("DEVICE_REGISTERED", "SUCCESS", token.userId, deviceId, correlationId = CorrelationIds.current())
            return DeviceEnrollmentResult(token.userId, deviceId, 1, pair.accessToken, pair.refreshToken)
        } catch (exception: DataAccessException) {
            val code = deviceConstraintCode(exception) ?: throw exception
            registrationFailure(token.userId, code)
        }
    }

    fun list(userId: UUID): List<DeviceView> = devices.list(userId)

    @Transactional
    fun updateFcm(
        userId: UUID,
        principalDeviceId: UUID,
        deviceId: UUID,
        fcmToken: String?,
    ) {
        if (principalDeviceId != deviceId) {
            throw ApiException(HttpStatus.FORBIDDEN, "AUTH_FORBIDDEN", "The request is not permitted.")
        }
        if (devices.updateFcmToken(userId, deviceId, fcmToken) == 0) {
            throw ApiException(HttpStatus.NOT_FOUND, "DEVICE_NOT_FOUND", "Device was not found.")
        }
    }

    @Transactional
    fun revoke(
        userId: UUID,
        principalDeviceId: UUID,
        deviceId: UUID,
    ) {
        val principalRole =
            devices.activeRole(userId, principalDeviceId)
                ?: throw ApiException(HttpStatus.FORBIDDEN, "DEVICE_REVOKED", "The device is unavailable.")
        val targetRole =
            devices.activeRole(userId, deviceId)
                ?: throw ApiException(HttpStatus.NOT_FOUND, "DEVICE_NOT_FOUND", "Device was not found.")
        if (principalDeviceId != deviceId && !(principalRole == "MAIN" && targetRole == "SOURCE")) {
            throw ApiException(HttpStatus.FORBIDDEN, "AUTH_FORBIDDEN", "The request is not permitted.")
        }
        if (devices.revoke(userId, deviceId) == 0) {
            throw ApiException(HttpStatus.NOT_FOUND, "DEVICE_NOT_FOUND", "Device was not found.")
        }
        sessions.revokeForDevice(userId, deviceId)
        audit.append("DEVICE_REVOKED", "SUCCESS", userId, deviceId, correlationId = CorrelationIds.current())
    }

    private fun validateInput(input: DeviceEnrollment) {
        if (input.role !in setOf("MAIN", "SOURCE") ||
            input.signingPublicKey.size != 32 ||
            input.encryptionPublicKey.size != 32 ||
            input.proofSignature.size != 64
        ) {
            throw ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_FAILED", "The request is not valid.")
        }
    }

    private fun verifyProof(
        challenge: ByteArray,
        input: DeviceEnrollment,
    ): Boolean =
        runCatching {
            val verifier = Signature.getInstance("Ed25519")
            verifier.initVerify(KeyFactory.getInstance("Ed25519").generatePublic(X509EncodedKeySpec(ed25519X509(input.signingPublicKey))))
            verifier.update(canonicalProofBytes(challenge, input))
            verifier.verify(input.proofSignature)
        }.getOrDefault(false)

    private fun canonicalProofBytes(
        challenge: ByteArray,
        input: DeviceEnrollment,
    ): ByteArray =
        CanonicalJson
            .encode(
                mapOf(
                    "appVersion" to input.appVersion,
                    "challenge" to encode(challenge),
                    "displayName" to input.displayName,
                    "encryptionPublicKey" to encode(input.encryptionPublicKey),
                    "platform" to input.platform,
                    "purpose" to "mirrorline-device-enrollment-v1",
                    "role" to input.role,
                    "signingPublicKey" to encode(input.signingPublicKey),
                ),
            ).toByteArray()

    private fun ed25519X509(raw: ByteArray): ByteArray =
        "302a300506032b6570032100".chunked(2).map { it.toInt(16).toByte() }.toByteArray() + raw

    private fun registrationFailure(
        userId: UUID?,
        code: String,
    ): Nothing {
        failureAudit.append("DEVICE_REGISTRATION", "FAILURE", userId, correlationId = CorrelationIds.current(), failureCode = code)
        throw ApiException(HttpStatus.FORBIDDEN, code, "Device registration could not be completed.")
    }

    private fun deviceConstraintCode(exception: DataAccessException): String? = enrollmentConstraintCode(exception)

    companion object {
        internal fun enrollmentConstraintCode(exception: DataAccessException): String? {
            val messages = mutableListOf<String>()
            var cause: Throwable? = exception
            while (cause != null) {
                messages += cause.message.orEmpty()
                cause = cause.cause
            }
            val message = messages.joinToString(" ")
            return when {
                message.contains("five active source") -> "DEVICE_LIMIT_REACHED"
                message.contains("uq_devices_one_active_main_per_user") -> "DEVICE_ROLE_CONFLICT"
                else -> null
            }
        }
    }
}
