package io.github.yildizib.mirrorline

import org.junit.Assert.assertEquals
import org.junit.Test

class NativeEventRouterTest {
    @Test
    fun `buffers FIFO until attached and ready`() {
        val router = BufferedNativeEventRouter()
        val delivered = mutableListOf<String>()

        router.route(NativeEvent("first", null))
        router.attach { delivered += it.event.method }
        router.route(NativeEvent("second", null))
        assertEquals(emptyList<String>(), delivered)

        router.setReady(true)
        assertEquals(listOf("first", "second"), delivered)
    }

    @Test
    fun `listener first event survives startup ordering`() {
        val router = BufferedNativeEventRouter()
        val delivered = mutableListOf<String>()
        router.route(NativeEvent("onNotification", mapOf("id" to "cold")))
        router.setReady(true)
        router.attach { delivered += it.event.method }
        assertEquals(listOf("onNotification"), delivered)
    }

    @Test
    fun `not ready clears stale pairing events`() {
        val router = BufferedNativeEventRouter()
        val delivered = mutableListOf<String>()
        router.route(NativeEvent("old-pairing", null))
        router.setReady(false)
        router.attach { delivered += it.event.method }
        router.route(NativeEvent("new-pairing", null))
        router.setReady(true)

        assertEquals(listOf("new-pairing"), delivered)
    }

    @Test
    fun `old lifecycle generation cannot route after reset`() {
        val router = BufferedNativeEventRouter()
        val oldGeneration = router.generation()
        router.setReady(false)

        assertEquals(
            false,
            router.route(NativeEvent("stale-async-work", null), oldGeneration),
        )
        assertEquals(0, router.pendingCount())
    }

    @Test
    fun `sink delivery remains revocable until deferred invocation`() {
        val router = BufferedNativeEventRouter()
        var deferred: NativeEventDelivery? = null
        router.attach { deferred = it }
        router.setReady(true)
        router.route(NativeEvent("posted-to-main", null))

        router.setReady(false)

        assertEquals(false, deferred?.isCurrent())
    }
}
