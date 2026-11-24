package io.github.yildizib.mirrorline.server.pairing

import io.github.yildizib.mirrorline.server.identity.AuthenticatedPrincipal
import io.github.yildizib.mirrorline.server.shared.ApiException
import jakarta.validation.Valid
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import org.springframework.http.HttpStatus
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.validation.annotation.Validated
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController
import java.util.Base64
import java.util.UUID

data class RedeemPairingRequest(
    @field:NotBlank @field:Pattern(regexp = "[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{10}") val code: String,
)

data class PairingProofRequest(
    @field:NotBlank @field:Size(max = 128) val signature: String,
)

data class PairingConfirmationRequest(
    val matches: Boolean,
)

@RestController
@Validated
@RequestMapping("/v1/pairings")
class PairingController(
    private val facade: PairingFacade,
) {
    @PostMapping
    fun create(
        @AuthenticationPrincipal principal: AuthenticatedPrincipal,
        @RequestHeader("Idempotency-Key") @NotBlank @Size(max = 128) key: String,
    ): PairingCreated = facade.create(principal, key)

    @PostMapping("/{pairingId}/redeem")
    fun redeem(
        @AuthenticationPrincipal principal: AuthenticatedPrincipal,
        @PathVariable pairingId: UUID,
        @Valid @RequestBody request: RedeemPairingRequest,
        @RequestHeader("Idempotency-Key") @NotBlank @Size(max = 128) key: String,
    ): PairingView = facade.redeem(principal, pairingId, request.code, key)

    @GetMapping("/{pairingId}")
    fun status(
        @AuthenticationPrincipal principal: AuthenticatedPrincipal,
        @PathVariable pairingId: UUID,
    ): PairingView = facade.status(principal, pairingId)

    @PostMapping("/{pairingId}/proofs")
    fun proof(
        @AuthenticationPrincipal principal: AuthenticatedPrincipal,
        @PathVariable pairingId: UUID,
        @Valid @RequestBody request: PairingProofRequest,
        @RequestHeader("Idempotency-Key") @NotBlank @Size(max = 128) key: String,
    ): PairingView = facade.proof(principal, pairingId, decode(request.signature), key)

    @PostMapping("/{pairingId}/comparison-confirmations")
    fun confirmation(
        @AuthenticationPrincipal principal: AuthenticatedPrincipal,
        @PathVariable pairingId: UUID,
        @Valid @RequestBody request: PairingConfirmationRequest,
        @RequestHeader("Idempotency-Key") @NotBlank @Size(max = 128) key: String,
    ): PairingView = facade.confirm(principal, pairingId, request.matches, key)

    @DeleteMapping("/{pairingId}")
    fun cancel(
        @AuthenticationPrincipal principal: AuthenticatedPrincipal,
        @PathVariable pairingId: UUID,
        @RequestHeader("Idempotency-Key") @NotBlank @Size(max = 128) key: String,
    ): PairingView = facade.cancel(principal, pairingId, key)

    private fun decode(value: String): ByteArray =
        if (value.length != 86 || value.contains('=')) {
            throw ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_FAILED", "The request is not valid.")
        } else {
            runCatching {
                Base64.getUrlDecoder().decode(value)
            }.getOrElse { throw ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_FAILED", "The request is not valid.") }
                .takeIf { it.size == 64 && Base64.getUrlEncoder().withoutPadding().encodeToString(it) == value }
                ?: throw ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_FAILED", "The request is not valid.")
        }
}
