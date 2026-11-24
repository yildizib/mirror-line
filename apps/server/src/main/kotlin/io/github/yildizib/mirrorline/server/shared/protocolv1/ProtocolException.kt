package io.github.yildizib.mirrorline.server.shared.protocolv1

enum class ProtocolErrorCode {
    UNSUPPORTED_VERSION,
    MALFORMED_INPUT,
    OVERSIZED_INPUT,
    AUTHENTICATION_FAILED,
}

class ProtocolException(
    val code: ProtocolErrorCode,
    message: String,
) : RuntimeException(message)
