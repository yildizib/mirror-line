package io.github.yildizib.mirrorline

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log

/**
 * Best-effort recovery for ROMs (observed on HyperOS/MIUI) that kill the
 * whole process outright instead of calling Service.onDestroy() -- when
 * that happens, neither START_STICKY nor onTaskRemoved's restart (see
 * MirrorLineService) ever runs, because both require the OS to go through
 * the normal service teardown path. An AlarmManager alarm is OS-owned, not
 * tied to this process, so it survives that kind of kill and can bring the
 * service back.
 *
 * This intentionally uses an inexact alarm and is only armed while native
 * lifecycle policy says mirroring is eligible.
 */
object Watchdog {
    private const val CHECK_INTERVAL_MS = 5 * 60 * 1000L // 5 minutes

    fun schedule(context: Context) {
        val (state, permissions) = MirroringServiceController.lifecycle(context)
        if (!WatchdogPolicy.shouldArm(state, permissions)) {
            cancel(context)
            return
        }
        try {
            val appContext = context.applicationContext
            val alarmManager =
                appContext.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val intent = Intent(appContext, WatchdogReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                appContext,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val triggerAt = SystemClock.elapsedRealtime() + CHECK_INTERVAL_MS

            alarmManager.setAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                triggerAt,
                pendingIntent
            )
        } catch (e: Exception) {
            Log.e("MirrorLine", "Failed to schedule watchdog alarm: ${e.message}", e)
        }
    }

    fun cancel(context: Context) {
        try {
            val appContext = context.applicationContext
            val alarmManager = appContext.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                ?: return
            val pendingIntent = PendingIntent.getBroadcast(
                appContext,
                0,
                Intent(appContext, WatchdogReceiver::class.java),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            ) ?: return
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        } catch (e: Exception) {
            Log.w("MirrorLine", "Failed to cancel watchdog alarm: ${e.message}")
        }
    }
}

object WatchdogPolicy {
    fun shouldArm(state: MirroringLifecycleState, permissionsGranted: Boolean): Boolean =
        MirroringLifecyclePolicy.isEligible(state, permissionsGranted)
}
