package io.github.yildizib.mirrorline

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
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
        MirrorLineEngine.getOrCreate(appContext)

        if (MirrorLineChannel.hasAllPermissions(appContext)) {
            val serviceIntent = Intent(appContext, MirrorLineService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    appContext.startForegroundService(serviceIntent)
                } else {
                    appContext.startService(serviceIntent)
                }
            } catch (e: Exception) {
                Log.e("MirrorLine", "Watchdog failed to (re)start service: ${e.message}", e)
            }
        }

        // Re-arm regardless of whether we (re)started the service above --
        // this chain needs to keep running for as long as the app is
        // installed and permissioned, not just while mirroring is active.
        Watchdog.schedule(appContext)
    }
}
