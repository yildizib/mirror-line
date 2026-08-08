package com.thinksolve.mirrorline

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class MirrorLineNotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val n = sbn?.notification ?: return
        val packageName = sbn.packageName ?: "unknown"
        if (packageName == this.packageName) return
        val extras = n.extras

        val title = extras.getString(Notification.EXTRA_TITLE, "") ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val timestamp = sbn.postTime

        val payload = mapOf(
            "packageName" to packageName,
            "title" to title,
            "text" to if (bigText.isNotEmpty()) bigText else text,
            "timestamp" to timestamp,
            "id" to "${timestamp}_$packageName"
        )

        MainActivity.channel?.invokeMethod("onNotification", payload)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        val n = sbn?.notification ?: return
        val packageName = sbn.packageName ?: "unknown"
        if (packageName == this.packageName) return
        val timestamp = sbn.postTime

        val payload = mapOf(
            "packageName" to packageName,
            "id" to "${timestamp}_$packageName"
        )

        MainActivity.channel?.invokeMethod("onNotificationRemoved", payload)
    }
}