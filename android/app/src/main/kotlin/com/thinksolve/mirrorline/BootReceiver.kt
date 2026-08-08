package com.thinksolve.mirrorline

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Restarts the mirroring service after a device reboot without waiting for
 * the user to manually reopen the app -- otherwise mirroring stays
 * silently off (see MirrorLineChannel.startMirrorService) until they do.
 * Android exempts apps from the usual background-start restrictions when
 * starting a foreground service in direct response to BOOT_COMPLETED, so
 * this is allowed to call startForegroundService() headlessly.
 *
 * Only starts if permissions were already granted in an earlier session
 * (they persist across reboot); if not, there's nothing to do here -- the
 * normal in-app flow will ask once the user opens the app.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val appContext = context.applicationContext
        MirrorLineEngine.getOrCreate(appContext)

        if (!MirrorLineChannel.hasAllPermissions(appContext)) return

        val serviceIntent = Intent(appContext, MirrorLineService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            appContext.startForegroundService(serviceIntent)
        } else {
            appContext.startService(serviceIntent)
        }
    }
}
