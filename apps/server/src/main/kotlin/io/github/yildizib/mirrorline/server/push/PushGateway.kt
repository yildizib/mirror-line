package io.github.yildizib.mirrorline.server.push

/** Sends a content-free wake signal. Product data must never enter FCM. */
fun interface PushGateway {
    fun sendWakeSignal(deviceToken: String): PushDeliveryResult
}

data class PushDeliveryResult(
    val accepted: Boolean,
    val providerMessageId: String? = null,
)
