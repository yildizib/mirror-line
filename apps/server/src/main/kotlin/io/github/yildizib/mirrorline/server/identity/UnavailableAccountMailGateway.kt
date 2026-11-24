package io.github.yildizib.mirrorline.server.identity

import io.github.yildizib.mirrorline.server.shared.ApiException
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean
import org.springframework.http.HttpStatus
import org.springframework.mail.javamail.JavaMailSender
import org.springframework.stereotype.Component

/**
 * Lets non-mail deployments boot without pretending an account action was delivered.
 * Account operations that need an email fail safely until SMTP is configured.
 */
@Component
@ConditionalOnMissingBean(JavaMailSender::class)
class UnavailableAccountMailGateway : AccountMailGateway {
    override fun sendVerification(
        email: String,
        rawToken: String,
    ): Nothing = unavailable()

    override fun sendPasswordReset(
        email: String,
        rawToken: String,
    ): Nothing = unavailable()

    private fun unavailable(): Nothing =
        throw ApiException(HttpStatus.SERVICE_UNAVAILABLE, "SERVICE_UNAVAILABLE", "Account email is unavailable.")
}
