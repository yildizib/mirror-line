package io.github.yildizib.mirrorline.server.push

import com.google.firebase.messaging.AndroidConfig
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.Message
import org.springframework.context.annotation.Profile
import org.springframework.stereotype.Component

@Component
@Profile("prod")
class FirebasePushGateway(
    private val firebaseMessaging: FirebaseMessaging,
) : PushGateway {
    override fun sendWakeSignal(deviceToken: String): PushDeliveryResult {
        val message =
            Message
                .builder()
                .setToken(deviceToken)
                .setAndroidConfig(
                    AndroidConfig
                        .builder()
                        .setPriority(AndroidConfig.Priority.HIGH)
                        .build(),
                ).putData("signal", "sync")
                .build()
        val messageId = firebaseMessaging.send(message)
        return PushDeliveryResult(accepted = true, providerMessageId = messageId)
    }
}
