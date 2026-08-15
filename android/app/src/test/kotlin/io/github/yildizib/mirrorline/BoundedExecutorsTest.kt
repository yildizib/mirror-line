package io.github.yildizib.mirrorline

import java.util.concurrent.CountDownLatch
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertThrows
import org.junit.Test

class BoundedExecutorsTest {
    @Test
    fun `saturation rejects explicitly instead of discarding queued work`() {
        val executor = BoundedExecutors.single("saturation-test", capacity = 1)
        val release = CountDownLatch(1)
        try {
            executor.execute { release.await(2, TimeUnit.SECONDS) }
            executor.execute { release.await(2, TimeUnit.SECONDS) }

            assertThrows(RejectedExecutionException::class.java) {
                executor.execute {}
            }
        } finally {
            release.countDown()
            executor.shutdownNow()
        }
    }
}
