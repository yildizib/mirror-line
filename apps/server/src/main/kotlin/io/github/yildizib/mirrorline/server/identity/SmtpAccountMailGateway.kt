package io.github.yildizib.mirrorline.server.identity

import org.springframework.boot.autoconfigure.condition.ConditionalOnBean
import org.springframework.mail.SimpleMailMessage
import org.springframework.mail.javamail.JavaMailSender
import org.springframework.stereotype.Component

/** Raw action tokens are handed to SMTP once and are never persisted or logged. */
@Component
@ConditionalOnBean(JavaMailSender::class)
class SmtpAccountMailGateway(
    private val sender: JavaMailSender,
) : AccountMailGateway {
    override fun sendVerification(
        email: String,
        rawToken: String,
    ) = send(email, "MirrorLine verification", rawToken)

    override fun sendPasswordReset(
        email: String,
        rawToken: String,
    ) = send(email, "MirrorLine password reset", rawToken)

    private fun send(
        email: String,
        subject: String,
        rawToken: String,
    ) {
        sender.send(
            SimpleMailMessage().apply {
                setTo(email)
                this.subject = subject
                text = rawToken
            },
        )
    }
}
