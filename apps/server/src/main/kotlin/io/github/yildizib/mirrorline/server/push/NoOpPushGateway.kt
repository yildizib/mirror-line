package io.github.yildizib.mirrorline.server.push

import org.springframework.context.annotation.Profile
import org.springframework.stereotype.Component

@Component
@Profile("!prod")
class NoOpPushGateway : PushGateway {
    override fun sendWakeSignal(deviceToken: String) = PushDeliveryResult(accepted = false)
}
