package io.github.yildizib.mirrorline

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CallLogMatcherTest {
    private fun resolvedBaseline(rowId: Long? = null) = CallLogBaseline().apply {
        resolve(rowId)
    }

    @Test
    fun `matches bounded incoming call type and rejects unrelated calls`() {
        val window = CallWindow(
            10_000,
            20_000,
            CallDirection.INCOMING,
            resolvedBaseline(),
        )
        assertTrue(CallLogMatcher.accepts(1, 9_000, 1, window))
        assertTrue(CallLogMatcher.accepts(1, 10_000, 3, window))
        assertFalse(CallLogMatcher.accepts(1, 12_000, 2, window))
        assertFalse(CallLogMatcher.accepts(1, 30_000, 1, window))
    }

    @Test
    fun `outgoing window only accepts outgoing type`() {
        val window = CallWindow(
            100_000,
            120_000,
            CallDirection.OUTGOING,
            resolvedBaseline(),
        )
        assertTrue(CallLogMatcher.accepts(1, 55_000, 2, window))
        assertTrue(CallLogMatcher.accepts(1, 15_000, 2, window))
        assertFalse(CallLogMatcher.accepts(1, 55_000, 1, window))
        assertFalse(CallLogMatcher.accepts(1, -30_000, 2, window))
    }

    @Test
    fun `baseline rejects prior outgoing row and accepts newer current row`() {
        val window = CallWindow(
            100_000,
            120_000,
            CallDirection.OUTGOING,
            resolvedBaseline(42),
        )

        assertFalse(CallLogMatcher.accepts(42, 55_000, 2, window))
        assertTrue(CallLogMatcher.accepts(43, 55_000, 2, window))
    }

    @Test
    fun `unresolved baseline rejects rows until capture completes`() {
        val baseline = CallLogBaseline()
        val window = CallWindow(100_000, 120_000, CallDirection.OUTGOING, baseline)

        assertFalse(CallLogMatcher.accepts(43, 55_000, 2, window))
        baseline.resolve(42)
        assertTrue(CallLogMatcher.accepts(43, 55_000, 2, window))
    }

    @Test
    fun `ranking chooses current outgoing over previous and newer unrelated rows`() {
        val window = CallWindow(
            100_000,
            160_000,
            CallDirection.OUTGOING,
            resolvedBaseline(42),
        )
        val selected = CallLogMatcher.selectBest(
            listOf(
                CallLogCandidate(42, 90_000, 2, 60_000),
                CallLogCandidate(43, 55_000, 2, 60_000),
                CallLogCandidate(44, 101_000, 2, 10_000),
            ),
            window,
        )

        assertEquals(43L, selected?.rowId)
    }

    @Test
    fun `ranking chooses duration-compatible incoming row`() {
        val window = CallWindow(
            100_000,
            160_000,
            CallDirection.INCOMING,
            resolvedBaseline(10),
        )
        val selected = CallLogMatcher.selectBest(
            listOf(
                CallLogCandidate(11, 100_000, 1, 60_000),
                CallLogCandidate(12, 100_500, 1, 5_000),
                CallLogCandidate(13, 100_000, 2, 60_000),
            ),
            window,
        )

        assertEquals(11L, selected?.rowId)
    }
}
