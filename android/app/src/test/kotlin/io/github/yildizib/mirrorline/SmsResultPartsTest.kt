package io.github.yildizib.mirrorline

import org.junit.Assert.assertEquals
import org.junit.Test

class SmsResultPartsTest {
    @Test
    fun `waits for each distinct multipart result and ignores duplicates`() {
        val parts = SmsResultParts(2)

        parts.record(0, true)
        parts.record(0, false)

        assertEquals(null, parts.finalSuccess())
        parts.record(1, true)
        assertEquals(true, parts.finalSuccess())
    }

    @Test
    fun `reports failure when any distinct part fails`() {
        val parts = SmsResultParts(2)

        parts.record(0, true)
        parts.record(1, false)

        assertEquals(false, parts.finalSuccess())
    }
}
