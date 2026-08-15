package io.github.yildizib.mirrorline

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class KeyedDrainQueueTest {
    @Test
    fun `reposts coalesce while distinct keys remain FIFO`() {
        val queue = KeyedDrainQueue<String, String>()
        queue.put("a", "a-old")
        queue.put("b", "b")
        queue.put("a", "a-new")

        assertEquals(2, queue.size())
        assertEquals("a-new", queue.poll())
        assertEquals("b", queue.poll())
        assertNull(queue.poll())
    }

    @Test
    fun `arrivals during drain are visible to the same drain loop`() {
        val queue = KeyedDrainQueue<String, String>()
        queue.put("first", "first")

        assertEquals("first", queue.poll())
        queue.put("during-drain", "during-drain")

        assertEquals("during-drain", queue.poll())
        assertNull(queue.poll())
    }

    @Test
    fun `clear invalidates all pending keys`() {
        val queue = KeyedDrainQueue<String, String>()
        queue.put("a", "a")
        queue.put("b", "b")
        queue.clear()

        assertEquals(true, queue.isEmpty())
        assertNull(queue.poll())
    }
}
