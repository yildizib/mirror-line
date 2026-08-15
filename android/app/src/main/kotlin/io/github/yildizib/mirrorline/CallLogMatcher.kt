package io.github.yildizib.mirrorline

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

enum class CallDirection { INCOMING, OUTGOING }

data class CallWindow(
    val startedAtMs: Long,
    val endedAtMs: Long,
    val direction: CallDirection,
    val baseline: CallLogBaseline,
)

data class CallLogCandidate(
    val rowId: Long,
    val dateMs: Long,
    val type: Int,
    val durationMs: Long?,
)

data class CallLogBaselineSnapshot(val resolved: Boolean, val rowId: Long?)

class CallLogBaseline {
    private val resolvedSignal = CountDownLatch(1)
    @Volatile
    private var snapshot = CallLogBaselineSnapshot(false, null)

    @Synchronized
    fun resolve(rowId: Long?) {
        if (snapshot.resolved) return
        snapshot = CallLogBaselineSnapshot(true, rowId)
        resolvedSignal.countDown()
    }

    fun snapshot(): CallLogBaselineSnapshot = snapshot

    fun await(timeoutMs: Long): CallLogBaselineSnapshot {
        resolvedSignal.await(timeoutMs, TimeUnit.MILLISECONDS)
        return snapshot
    }
}

object CallLogMatcher {
    const val START_TOLERANCE_MS = 2_000L
    const val OUTGOING_LOOKBACK_MS = 2 * 60 * 1000L
    const val END_TOLERANCE_MS = 5_000L

    fun accepts(rowId: Long, dateMs: Long, type: Int, window: CallWindow): Boolean {
        val baseline = window.baseline.snapshot()
        if (!baseline.resolved) return false
        if (baseline.rowId != null && rowId <= baseline.rowId) return false
        val directionMatches = when (window.direction) {
            CallDirection.INCOMING -> type == 1 || type == 3
            CallDirection.OUTGOING -> type == 2
        }
        return directionMatches &&
            dateMs >= lowerBoundMs(window) &&
            dateMs <= window.endedAtMs + END_TOLERANCE_MS
    }

    fun selectBest(
        candidates: List<CallLogCandidate>,
        window: CallWindow,
    ): CallLogCandidate? = candidates
        .asSequence()
        .filter { accepts(it.rowId, it.dateMs, it.type, window) }
        .minWithOrNull(
            compareBy<CallLogCandidate> { candidateScore(it, window) }
                .thenByDescending { it.rowId },
        )

    private fun candidateScore(candidate: CallLogCandidate, window: CallWindow): Long {
        val startDistance = kotlin.math.abs(candidate.dateMs - window.startedAtMs)
        val sessionDuration = (window.endedAtMs - window.startedAtMs).coerceAtLeast(0L)
        val durationDistance = candidate.durationMs?.let {
            kotlin.math.abs(it - sessionDuration)
        } ?: 0L
        return startDistance + durationDistance * DURATION_WEIGHT
    }

    fun lowerBoundMs(window: CallWindow): Long = window.startedAtMs - when (window.direction) {
        CallDirection.INCOMING -> START_TOLERANCE_MS
        CallDirection.OUTGOING -> OUTGOING_LOOKBACK_MS
    }

    private const val DURATION_WEIGHT = 2L
}
