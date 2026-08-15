package io.github.yildizib.mirrorline

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SmsAssemblerTest {
    @Test
    fun `assembles parts within one intent but keeps rapid messages separate`() {
        val first = SmsAssembler.assemble(
            listOf(SmsPart("123", "hello ", 100), SmsPart("123", "world", 105)),
        ).single()
        val second = SmsAssembler.assemble(listOf(SmsPart("123", "again", 101))).single()

        assertEquals("hello world", first.body)
        assertEquals("again", second.body)
        assertFalse(first.fingerprint == second.fingerprint)
    }

    @Test
    fun `separate intents from same sender remain separate`() {
        val firstIntent = SmsAssembler.assemble(listOf(SmsPart("123", "one", 100))).single()
        val secondIntent = SmsAssembler.assemble(listOf(SmsPart("123", "two", 101))).single()

        assertEquals("one", firstIntent.body)
        assertEquals("two", secondIntent.body)
    }

    @Test
    fun `suppresses exact fingerprints only`() {
        val cache = ExactFingerprintCache()
        assertTrue(cache.addIfNew("same"))
        assertFalse(cache.addIfNew("same"))
        assertTrue(cache.addIfNew("different"))
    }
}
