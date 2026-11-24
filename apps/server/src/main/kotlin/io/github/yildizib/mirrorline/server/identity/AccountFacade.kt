package io.github.yildizib.mirrorline.server.identity

import io.github.yildizib.mirrorline.server.shared.ApiException
import io.github.yildizib.mirrorline.server.shared.CorrelationIds
import io.github.yildizib.mirrorline.server.shared.FailureSecurityAuditService
import io.github.yildizib.mirrorline.server.shared.SecurityAuditPersistenceRepository
import org.springframework.http.HttpStatus
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.Base64
import java.util.UUID

data class TokenPair(
    val userId: UUID,
    val deviceId: UUID,
    val accessToken: String,
    val refreshToken: String,
)

data class EnrollmentGrant(
    val userId: UUID,
    val token: String,
    val challenge: String,
)

data class LoginResult(
    val tokens: TokenPair? = null,
    val enrollment: EnrollmentGrant? = null,
)

@Service
class AccountFacade(
    private val accounts: AccountRepository,
    private val actions: AccountActionTokenRepository,
    private val sessions: SessionRepository,
    private val mail: AccountMailGateway,
    private val passwordEncoder: PasswordEncoder,
    private val audit: SecurityAuditPersistenceRepository,
    private val failureAudit: FailureSecurityAuditService,
    private val deviceLookup: DeviceSessionLookup,
) {
    @Transactional
    fun register(
        email: String,
        password: String,
    ): UUID {
        val normalized = normalizeEmail(email)
        val userId = accounts.create(normalized, passwordEncoder.encode(password)!!)
        if (userId == null) {
            failureAudit.append(
                "ACCOUNT_REGISTERED",
                "FAILURE",
                correlationId = CorrelationIds.current(),
                failureCode = "VALIDATION_FAILED",
            )
            throw ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_FAILED", "The request is not valid.")
        }
        issueMailToken(userId, normalized, "EMAIL_VERIFICATION", 24.0)
        audit.append("ACCOUNT_REGISTERED", "SUCCESS", userId, correlationId = CorrelationIds.current())
        return userId
    }

    @Transactional
    fun verifyEmail(rawToken: String) {
        val token =
            actions.consume("EMAIL_VERIFICATION", hash(rawToken))
                ?: throw ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_FAILED", "The request is not valid.")
        accounts.markEmailVerified(token.userId)
        audit.append("EMAIL_VERIFIED", "SUCCESS", token.userId, correlationId = CorrelationIds.current())
    }

    @Transactional
    fun login(
        email: String,
        password: String,
        deviceId: UUID?,
    ): LoginResult {
        val account = accounts.findByEmail(normalizeEmail(email))
        val passwordMatches = passwordEncoder.matches(password, account?.passwordHash ?: DUMMY_PASSWORD_HASH)
        if (account == null || account.status != "ACTIVE" || !passwordMatches) {
            failureAudit.append(
                "LOGIN",
                "FAILURE",
                account?.userId,
                correlationId = CorrelationIds.current(),
                failureCode = "AUTH_INVALID_CREDENTIALS",
            )
            throw ApiException(HttpStatus.UNAUTHORIZED, "AUTH_INVALID_CREDENTIALS", "Invalid credentials.")
        }
        if (account.verifiedAt == null) {
            failureAudit.append("LOGIN", "DENIED", account.userId, correlationId = CorrelationIds.current())
            throw ApiException(HttpStatus.FORBIDDEN, "AUTH_FORBIDDEN", "Email verification is required.")
        }
        if (deviceId == null) {
            val raw = randomToken()
            val challenge = randomBytes()
            actions.create(account.userId, "DEVICE_ENROLLMENT", hash(raw), now().plusMinutes(10), challenge)
            audit.append("LOGIN_ENROLLMENT", "SUCCESS", account.userId, correlationId = CorrelationIds.current())
            return LoginResult(enrollment = EnrollmentGrant(account.userId, raw, encode(challenge)))
        }
        if (!deviceLookup.isActive(account.userId, deviceId)) {
            failureAudit.append("LOGIN", "DENIED", account.userId, deviceId, correlationId = CorrelationIds.current())
            throw ApiException(HttpStatus.FORBIDDEN, "DEVICE_REVOKED", "The device is unavailable.")
        }
        val tokens = createSession(account.userId, deviceId)
        accounts.recordSuccessfulLogin(account.userId)
        audit.append("LOGIN", "SUCCESS", account.userId, deviceId, correlationId = CorrelationIds.current())
        return LoginResult(tokens = tokens)
    }

    @Transactional
    fun refresh(rawRefresh: String): TokenPair {
        val access = randomToken()
        val refresh = randomToken()
        val session =
            sessions.rotateRefresh(
                hash(rawRefresh),
                hash(access),
                now().plusMinutes(15),
                hash(refresh),
                now().plusDays(30),
            ) ?: throw ApiException(HttpStatus.UNAUTHORIZED, "AUTH_SESSION_EXPIRED", "Session is unavailable.")
        audit.append(
            "SESSION_REFRESHED",
            "SUCCESS",
            session.userId,
            session.deviceId,
            sessionId = session.sessionId,
            correlationId = CorrelationIds.current(),
        )
        return TokenPair(session.userId, session.deviceId, access, refresh)
    }

    @Transactional
    fun requestPasswordReset(email: String) {
        accounts.findByEmail(normalizeEmail(email))?.takeIf { it.verifiedAt != null }?.let { account ->
            issueMailToken(account.userId, account.email, "PASSWORD_RESET", 0.5)
            audit.append("PASSWORD_RESET_REQUEST", "SUCCESS", account.userId, correlationId = CorrelationIds.current())
        } ?: run {
            audit.append("PASSWORD_RESET_REQUEST", "SUCCESS", correlationId = CorrelationIds.current())
        }
    }

    @Transactional
    fun resetPassword(
        rawToken: String,
        password: String,
    ) {
        val token =
            actions.consume("PASSWORD_RESET", hash(rawToken))
                ?: throw ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_FAILED", "The request is not valid.")
        accounts.updatePassword(token.userId, passwordEncoder.encode(password)!!)
        sessions.revokeAll(token.userId)
        audit.append("PASSWORD_RESET", "SUCCESS", token.userId, correlationId = CorrelationIds.current())
    }

    fun authenticate(rawAccess: String): SessionRecord? = sessions.findActiveAccess(hash(rawAccess))

    @Transactional
    fun logout(
        userId: UUID,
        sessionId: UUID,
    ) {
        sessions.revoke(userId, sessionId)
        audit.append("SESSION_LOGOUT", "SUCCESS", userId, sessionId = sessionId, correlationId = CorrelationIds.current())
    }

    @Transactional
    fun revokeSession(
        userId: UUID,
        sessionId: UUID,
    ) {
        if (sessions.revoke(userId, sessionId) == 0) {
            throw ApiException(HttpStatus.NOT_FOUND, "AUTH_SESSION_EXPIRED", "Session is unavailable.")
        }
        audit.append("SESSION_REVOKED", "SUCCESS", userId, sessionId = sessionId, correlationId = CorrelationIds.current())
    }

    fun sessions(userId: UUID): List<SessionView> = sessions.listForUser(userId)

    @Transactional
    fun createSession(
        userId: UUID,
        deviceId: UUID,
    ): TokenPair {
        val access = randomToken()
        val refresh = randomToken()
        val session = sessions.create(userId, deviceId, hash(access), now().plusMinutes(15), hash(refresh), now().plusDays(30))
        return TokenPair(session.userId, session.deviceId, access, refresh)
    }

    fun recordDeviceBoundLogin(userId: UUID) = accounts.recordSuccessfulLogin(userId)

    private fun issueMailToken(
        userId: UUID,
        email: String,
        kind: String,
        hours: Double,
    ) {
        val raw = randomToken()
        actions.create(userId, kind, hash(raw), now().plusSeconds((hours * 3600).toLong()))
        if (kind == "EMAIL_VERIFICATION") mail.sendVerification(email, raw) else mail.sendPasswordReset(email, raw)
    }

    private fun normalizeEmail(email: String): String = email.trim().lowercase()

    private fun now(): OffsetDateTime = OffsetDateTime.now(ZoneOffset.UTC)

    companion object {
        private val random = SecureRandom()

        fun hash(value: String): ByteArray = MessageDigest.getInstance("SHA-256").digest(value.toByteArray())

        fun hash(value: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(value)

        fun encode(value: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(value)

        fun randomBytes(): ByteArray = ByteArray(32).also(random::nextBytes)

        fun randomToken(): String = encode(randomBytes())

        private const val DUMMY_PASSWORD_HASH = "\$2a\$12\$Fq9J5FwWn.kmti61a2Cz8uJxSg5NFWq0nd8KYT7tB0r5J6KGZhXKa"
    }
}

@Service
class DeviceSessionLookup(
    private val devices: io.github.yildizib.mirrorline.server.devices.DeviceAccountRepository,
) {
    fun isActive(
        userId: UUID,
        deviceId: UUID,
    ): Boolean = devices.existsActive(userId, deviceId)
}
