package io.github.yildizib.mirrorline

import java.util.concurrent.atomic.AtomicLong

data class CallSession(
    val id: String,
    val startedAtMs: Long,
    val direction: CallDirection,
    val lifecycleGeneration: Long,
    val callLogBaseline: CallLogBaseline,
)

class CallSessionFactory {
    private val counter = AtomicLong()

    fun create(
        startedAtMs: Long,
        direction: CallDirection,
        lifecycleGeneration: Long = 0,
    ): CallSession = CallSession(
        id = "$startedAtMs-${counter.incrementAndGet()}",
        startedAtMs = startedAtMs,
        direction = direction,
        lifecycleGeneration = lifecycleGeneration,
        callLogBaseline = CallLogBaseline(),
    )
}
