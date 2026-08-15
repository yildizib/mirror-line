package io.github.yildizib.mirrorline

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class CallSessionTest {
    @Test
    fun `overlapping async work retains original session id`() {
        val factory = CallSessionFactory()
        val callA = factory.create(1_000, CallDirection.INCOMING)
        val delayedTerminalSessionId = callA.id
        val callB = factory.create(2_000, CallDirection.INCOMING)
        callA.callLogBaseline.resolve(41)

        assertNotEquals(callA.id, callB.id)
        assertEquals(callA.id, delayedTerminalSessionId)
        assertEquals("1000-1", callA.id)
        assertEquals("2000-2", callB.id)
        assertEquals(41L, callA.callLogBaseline.snapshot().rowId)
        assertEquals(false, callB.callLogBaseline.snapshot().resolved)
    }
}
