package io.github.yildizib.mirrorline.server.identity

interface AccountMailGateway {
    fun sendVerification(
        email: String,
        rawToken: String,
    )

    fun sendPasswordReset(
        email: String,
        rawToken: String,
    )
}
