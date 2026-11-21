package io.github.yildizib.mirrorline.server.push

import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test

class NoOpPushGatewayTest {
    @Test
    fun `development gateway never reports delivery`() {
        val result = NoOpPushGateway().sendWakeSignal("unused-token")
        assertThat(result.accepted).isFalse()
        assertThat(result.providerMessageId).isNull()
    }
}
