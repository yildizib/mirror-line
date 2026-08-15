package io.github.yildizib.mirrorline

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Fired periodically by Watchdog's self-re-arming alarm. Always
 * (re)starts MirrorLineService -- if it's already running, onStartCommand's
 * work (channel/notification/receivers/locks) is idempotent, so this is a
 * harmless no-op; if the process was killed outright (see Watchdog), this
 * is what actually brings it back instead of waiting for the user to
 * reopen the app.
 */
class WatchdogReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val appContext = context.applicationContext
        val result = MirroringServiceController.start(appContext)
        if (result.outcome == ServiceOutcome.FAILED) {
            Log.e("MirrorLine", "Watchdog failed to (re)start service: ${result.error}")
        }
        if (MirroringServiceController.isEligible(appContext)) Watchdog.schedule(appContext)
    }
}
