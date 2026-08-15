package io.github.yildizib.mirrorline

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

data class NativeEvent(val method: String, val arguments: Any?)

class NativeEventDelivery internal constructor(
    val event: NativeEvent,
    val generation: Long,
    private val generationIsCurrent: (Long) -> Boolean,
) {
    fun isCurrent(): Boolean = generationIsCurrent(generation)
}

class BufferedNativeEventRouter {
    private val pending = ArrayDeque<NativeEvent>()
    private var sink: ((NativeEventDelivery) -> Unit)? = null
    private var ready = false
    private var generation = 0L

    @Synchronized
    fun attach(sink: (NativeEventDelivery) -> Unit) {
        this.sink = sink
        flushIfReady()
    }

    @Synchronized
    fun detach() {
        sink = null
        ready = false
        pending.clear()
        generation++
    }

    @Synchronized
    fun setReady(value: Boolean) {
        if (value) {
            ready = true
            flushIfReady()
        } else {
            ready = false
            pending.clear()
            generation++
        }
    }

    @Synchronized
    fun route(event: NativeEvent, expectedGeneration: Long? = null): Boolean {
        if (expectedGeneration != null && expectedGeneration != generation) return false
        val currentSink = sink
        if (!ready || currentSink == null) {
            pending.addLast(event)
        } else {
            currentSink(delivery(event))
        }
        return true
    }

    @Synchronized
    fun pendingCount(): Int = pending.size

    @Synchronized
    fun generation(): Long = generation

    @Synchronized
    fun isGenerationCurrent(value: Long): Boolean = value == generation

    private fun flushIfReady() {
        val currentSink = sink ?: return
        if (!ready) return
        while (pending.isNotEmpty()) currentSink(delivery(pending.removeFirst()))
    }

    private fun delivery(event: NativeEvent) = NativeEventDelivery(
        event,
        generation,
        ::isGenerationCurrent,
    )
}

object NativeEventRouter {
    private val router = BufferedNativeEventRouter()
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    fun attach(channel: MethodChannel) {
        router.attach { delivery ->
            mainHandler.post {
                if (delivery.isCurrent()) {
                    channel.invokeMethod(delivery.event.method, delivery.event.arguments)
                }
            }
        }
    }

    fun ready() = router.setReady(true)

    fun notReady() = router.setReady(false)

    fun route(method: String, arguments: Any?) = router.route(NativeEvent(method, arguments))

    fun generation(): Long = router.generation()

    fun isGenerationCurrent(generation: Long): Boolean =
        router.isGenerationCurrent(generation)

    fun routeIfCurrent(generation: Long, method: String, arguments: Any?): Boolean =
        router.route(NativeEvent(method, arguments), generation)
}
