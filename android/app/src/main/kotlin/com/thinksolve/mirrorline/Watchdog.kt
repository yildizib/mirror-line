package com.thinksolve.mirrorline

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
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
 * On Android 12+, exact alarms are used if the SCHEDULE_EXACT_ALARM
 * permission is granted and canScheduleExactAlarms() returns true, ensuring
 * the alarm fires at the intended time rather than being deferred by Doze.
 * Falls back to inexact (setAndAllowWhileIdle) for older APIs or when the
 * system denies exact alarm permission.
 */
object Watchdog {
    private const val CHECK_INTERVAL_MS = 5 * 60 * 1000L // 5 minutes

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

            // Try exact alarm on Android 12+ if system permits it
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (alarmManager.canScheduleExactAlarms()) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAt,
                        pendingIntent
                    )
                    return
                }
            }

            // Fallback to inexact alarm for older APIs or when permission denied
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                triggerAt,
                pendingIntent
            )
        } catch (_: Exception) {
        }
    }
}
