package io.github.yildizib.mirrorline

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MirroringLifecyclePolicyTest {
    private val eligible = MirroringLifecycleState(true, true, "source", true)

    @Test
    fun `requires every lifecycle condition and permissions`() {
        assertTrue(MirroringLifecyclePolicy.isEligible(eligible, true))
        assertFalse(MirroringLifecyclePolicy.isEligible(eligible.copy(initialized = false), true))
        assertFalse(MirroringLifecyclePolicy.isEligible(eligible.copy(enabled = false), true))
        assertFalse(MirroringLifecyclePolicy.isEligible(eligible.copy(role = "main"), true))
        assertFalse(MirroringLifecyclePolicy.isEligible(eligible.copy(paired = false), true))
        assertFalse(MirroringLifecyclePolicy.isEligible(eligible, false))
    }

    @Test
    fun `watchdog only arms when eligible`() {
        assertTrue(WatchdogPolicy.shouldArm(eligible, true))
        assertFalse(WatchdogPolicy.shouldArm(eligible.copy(enabled = false), true))
    }

    @Test
    fun `network monitoring allows paired main without telephony permissions`() {
        assertTrue(
            MirroringLifecyclePolicy.shouldMonitorNetwork(eligible.copy(role = "main")),
        )
        assertFalse(
            MirroringLifecyclePolicy.shouldMonitorNetwork(eligible.copy(paired = false)),
        )
        assertFalse(
            MirroringLifecyclePolicy.shouldMonitorNetwork(eligible.copy(enabled = false)),
        )
    }
}
