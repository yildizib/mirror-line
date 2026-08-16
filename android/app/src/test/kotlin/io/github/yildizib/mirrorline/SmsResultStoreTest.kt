package io.github.yildizib.mirrorline

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
class SmsResultStoreTest {
    @Test
    fun `submission acceptance survives recreation until sent result acknowledgement`() {
        val context = RuntimeEnvironment.getApplication()
        val operationId = "submission-1"

        SmsResultStore(context).prepareSubmission(operationId)

        assertTrue(SmsResultStore(context).hasSubmission(operationId))
        SmsResultStore(context).acknowledge(operationId, SmsResultStore.SENT)
        assertTrue(!SmsResultStore(context).hasSubmission(operationId))
    }

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

    @Test
    fun `receiver instances retain concurrent callback updates`() {
        val context = RuntimeEnvironment.getApplication()
        val operationIds = (1..32).map { "concurrent-$it" }
        val start = CountDownLatch(1)
        val complete = CountDownLatch(operationIds.size)
        val executor = Executors.newFixedThreadPool(operationIds.size)

        operationIds.forEach { operationId ->
            executor.execute {
                start.await()
                SmsResultStore(context).record(
                    operationId,
                    SmsResultStore.SENT,
                    partIndex = 0,
                    partCount = 1,
                    success = true,
                )
                complete.countDown()
            }
        }
        start.countDown()

        assertTrue(complete.await(10, TimeUnit.SECONDS))
        executor.shutdown()
        assertEquals(
            operationIds.toSet(),
            SmsResultStore(context).pending().map { it.operationId }.toSet(),
        )
        operationIds.forEach {
            SmsResultStore(context).acknowledge(it, SmsResultStore.SENT)
        }
    }
}
