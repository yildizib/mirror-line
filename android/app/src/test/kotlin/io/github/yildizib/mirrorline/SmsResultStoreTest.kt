package io.github.yildizib.mirrorline

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class SmsResultStoreTest {
    @Test
    fun `result survives store recreation until Dart acknowledges it`() {
        val context = RuntimeEnvironment.getApplication()
        val operationId = "operation-1"

        assertEquals(
            null,
            SmsResultStore(context).record(
                operationId,
                SmsResultStore.SENT,
                partIndex = 0,
                partCount = 2,
                success = true,
            ),
        )
        assertEquals(
            SmsResult(operationId, SmsResultStore.SENT, true),
            SmsResultStore(context).record(
                operationId,
                SmsResultStore.SENT,
                partIndex = 1,
                partCount = 2,
                success = true,
            ),
        )

        val recreatedStore = SmsResultStore(context)
        assertEquals(
            listOf(SmsResult(operationId, SmsResultStore.SENT, true)),
            recreatedStore.pending(),
        )

        recreatedStore.acknowledge(operationId, SmsResultStore.SENT)

        assertTrue(SmsResultStore(context).pending().isEmpty())
    }
}
