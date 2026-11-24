package io.github.yildizib.mirrorline.server.identity

import io.github.yildizib.mirrorline.server.devices.DeviceEnrollment
import io.github.yildizib.mirrorline.server.devices.DeviceFacade
import io.github.yildizib.mirrorline.server.shared.ApiException
import jakarta.validation.Valid
import jakarta.validation.constraints.Email
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController
import java.util.Base64
import java.util.UUID

data class RegisterRequest(
    @field:Email @field:NotBlank @field:Size(max = 320) val email: String,
    @field:NotBlank
    @field:Size(min = 12, max = 256)
    @field:Pattern(regexp = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).+$")
    val password: String,
)

data class TokenRequest(
    @field:NotBlank @field:Size(max = 512) val token: String,
)

data class PasswordResetRequest(
    @field:Email @field:NotBlank @field:Size(max = 320) val email: String,
)

data class ResetPasswordRequest(
    @field:NotBlank @field:Size(max = 512) val token: String,
    @field:NotBlank
    @field:Size(min = 12, max = 256)
    @field:Pattern(regexp = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).+$")
    val password: String,
)

data class LoginRequest(
    @field:Email @field:NotBlank @field:Size(max = 320) val email: String,
    @field:NotBlank @field:Size(max = 256) val password: String,
    val deviceId: UUID? = null,
)

data class RefreshRequest(
    @field:NotBlank @field:Size(max = 512) val refreshToken: String,
)

data class TokenResponse(
    val userId: UUID,
    val deviceId: UUID,
    val accessToken: String,
    val refreshToken: String,
)

data class EnrollmentResponse(
    val userId: UUID,
    val enrollmentToken: String,
    val enrollmentChallenge: String,
)

data class LoginResponse(
    val tokens: TokenResponse? = null,
    val enrollment: EnrollmentResponse? = null,
)

data class DeviceEnrollmentRequest(
    @field:NotBlank @field:Size(max = 512) val enrollmentToken: String,
    @field:NotBlank val role: String,
    @field:NotBlank @field:Size(max = 32) val platform: String,
    @field:NotBlank @field:Size(max = 64) val appVersion: String,
    @field:NotBlank @field:Size(max = 128) val displayName: String,
    @field:NotBlank @field:Size(max = 128) val signingPublicKey: String,
    @field:NotBlank @field:Size(max = 128) val encryptionPublicKey: String,
    @field:NotBlank @field:Size(max = 128) val proofSignature: String,
)

data class DeviceEnrollmentResponse(
    val userId: UUID,
    val deviceId: UUID,
    val keyVersion: Int,
    val accessToken: String,
    val refreshToken: String,
)

data class FcmTokenRequest(
    @field:Size(max = 4096) val fcmToken: String?,
)

@RestController
@RequestMapping("/v1")
class IdentityController(
    private val accounts: AccountFacade,
    private val devices: DeviceFacade,
) {
    @PostMapping("/auth/register")
    fun register(
        @Valid @RequestBody request: RegisterRequest,
    ): ResponseEntity<Map<String, UUID>> =
        ResponseEntity.status(HttpStatus.ACCEPTED).body(mapOf("userId" to accounts.register(request.email, request.password)))

    @PostMapping("/auth/verify-email")
    fun verifyEmail(
        @Valid @RequestBody request: TokenRequest,
    ): ResponseEntity<Void> {
        accounts.verifyEmail(request.token)
        return ResponseEntity.noContent().build()
    }

    @PostMapping("/auth/login")
    fun login(
        @Valid @RequestBody request: LoginRequest,
    ): LoginResponse {
        val result = accounts.login(request.email, request.password, request.deviceId)
        return LoginResponse(
            result.tokens?.let { TokenResponse(it.userId, it.deviceId, it.accessToken, it.refreshToken) },
            result.enrollment?.let { EnrollmentResponse(it.userId, it.token, it.challenge) },
        )
    }

    @PostMapping("/auth/refresh")
    fun refresh(
        @Valid @RequestBody request: RefreshRequest,
    ): TokenResponse = accounts.refresh(request.refreshToken).toResponse()

    @PostMapping("/auth/forgot-password")
    fun forgotPassword(
        @Valid @RequestBody request: PasswordResetRequest,
    ): ResponseEntity<Void> {
        accounts.requestPasswordReset(request.email)
        return ResponseEntity.accepted().build()
    }

    @PostMapping("/auth/reset-password")
    fun resetPassword(
        @Valid @RequestBody request: ResetPasswordRequest,
    ): ResponseEntity<Void> {
        accounts.resetPassword(request.token, request.password)
        return ResponseEntity.noContent().build()
    }

    @PostMapping("/devices/enroll")
    fun enroll(
        @Valid @RequestBody request: DeviceEnrollmentRequest,
    ): DeviceEnrollmentResponse {
        val result =
            devices.enroll(
                DeviceEnrollment(
                    request.enrollmentToken,
                    request.role,
                    request.platform,
                    request.appVersion,
                    request.displayName,
                    decode(request.signingPublicKey),
                    decode(request.encryptionPublicKey),
                    decode(request.proofSignature),
                ),
            )
        return DeviceEnrollmentResponse(
            result.userId,
            result.deviceId,
            result.keyVersion,
            result.accessToken,
            result.refreshToken,
        )
    }

    @PostMapping("/auth/logout")
    fun logout(
        @AuthenticationPrincipal principal: AuthenticatedPrincipal,
    ): ResponseEntity<Void> {
        accounts.logout(principal.userId, principal.sessionId)
        return ResponseEntity.noContent().build()
    }

    @GetMapping("/sessions")
    fun sessions(
        @AuthenticationPrincipal principal: AuthenticatedPrincipal,
    ): List<SessionView> = accounts.sessions(principal.userId)

    @DeleteMapping("/sessions/{sessionId}")
    fun revokeSession(
        @AuthenticationPrincipal principal: AuthenticatedPrincipal,
        @PathVariable sessionId: UUID,
    ): ResponseEntity<Void> {
        accounts.revokeSession(principal.userId, sessionId)
        return ResponseEntity.noContent().build()
    }

    @GetMapping("/devices")
    fun devices(
        @AuthenticationPrincipal principal: AuthenticatedPrincipal,
    ) = devices.list(principal.userId)

    @PostMapping("/devices/{deviceId}/fcm-token")
    fun updateFcm(
        @AuthenticationPrincipal principal: AuthenticatedPrincipal,
        @PathVariable deviceId: UUID,
        @Valid @RequestBody request: FcmTokenRequest,
    ): ResponseEntity<Void> {
        devices.updateFcm(principal.userId, principal.deviceId, deviceId, request.fcmToken)
        return ResponseEntity.noContent().build()
    }

    @DeleteMapping("/devices/{deviceId}")
    fun revokeDevice(
        @AuthenticationPrincipal principal: AuthenticatedPrincipal,
        @PathVariable deviceId: UUID,
    ): ResponseEntity<Void> {
        devices.revoke(principal.userId, principal.deviceId, deviceId)
        return ResponseEntity.noContent().build()
    }

    private fun decode(value: String): ByteArray =
        runCatching { Base64.getUrlDecoder().decode(value) }.getOrElse {
            throw ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_FAILED", "The request is not valid.")
        }

    private fun TokenPair.toResponse(): TokenResponse = TokenResponse(userId, deviceId, accessToken, refreshToken)
}
