package com.thinksolve.mirrorline

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.SystemClock

/**
 * Best-effort recovery for ROMs (observed on HyperOS/MIUI) that kill the
 * whole process outright instead of calling Service.onDestroy() -- when
 * that happens, neither START_STICKY nor onTaskRemoved's restart (see
 * MirrorLineService) ever runs, because both require the OS to go through
 * the normal service teardown path. An AlarmManager alarm is OS-owned, not
 * tied to this process, so it survives that kind of kill and can bring the
 * service back.
 *
 * Deliberately inexact (setAndAllowWhileIdle, not setExactAndAllowWhileIdle):
 * this check doesn't need to-the-second precision, just to bound the outage
 * to roughly CHECK_INTERVAL_MS, and inexact alarms don't require the user to
 * separately grant SCHEDULE_EXACT_ALARM (Android 12+).
 */
object Watchdog {
    private const val CHECK_INTERVAL_MS = 15 * 60 * 1000L // 15 minutes

    fun schedule(context: Context) {
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
        } catch (_: Exception) {
        }
    }
}
