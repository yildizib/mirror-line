package io.github.yildizib.mirrorline

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class CallRejectionStoreTest {
    @Test
    fun `accepted rejection marker survives process recreation and is operation scoped`() {
        val context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("mirrorline_call_rejections", 0).edit().clear().commit()

        CallRejectionStore(context).record("accepted-command")

        val recreatedStore = CallRejectionStore(context)
        assertTrue(recreatedStore.hasRejection("accepted-command"))
        assertFalse(recreatedStore.hasRejection("different-command"))
    }
}
