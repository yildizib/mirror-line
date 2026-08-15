package io.github.yildizib.mirrorline

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CallRejectionResultTest {
    @Test
    fun `returns actual platform result without coercion`() {
        assertTrue(CallRejectionResult.actualBoolean(true))
        assertFalse(CallRejectionResult.actualBoolean(false))
        assertFalse(CallRejectionResult.actualBoolean(null))
    }
}
