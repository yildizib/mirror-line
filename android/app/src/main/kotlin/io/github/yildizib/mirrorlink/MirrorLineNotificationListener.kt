package io.github.yildizib.mirrorlink

import android.app.Notification
import android.content.pm.PackageManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class MirrorLineNotificationListener : NotificationListenerService() {

    // Android reposts the *same* logical notification repeatedly (preview
    // text tweaks, summary + child updates, etc.), each time with a fresh
    // postTime. Keying purely off postTime (the old behaviour) meant every
    // repost became a brand-new mirrored notification on the other phone.
    // sbn.key stays stable for the life of one logical notification, and
    // remembering the last content sent per key lets identical reposts be
    // skipped instead of duplicated.
    private val lastContentByKey = HashMap<String, String>()

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val packageName = sbn.packageName ?: "unknown"
        if (packageName == this.packageName) return

        // The default Phone/Dialer and SMS/Messages apps' own notifications
        // describe the exact same call/SMS events MirrorLineService already
        // reports through its dedicated, contact-resolved telephony bridge.
        // Mirroring them too would show every call and text twice.
        if (DefaultAppResolver.isDefaultDialerOrSms(this, packageName)) return

        // Grouped notifications (most messaging apps) post both a "summary"
        // (e.g. generic "3 new messages") and separate notifications for
        // each actual message. Mirroring both doubles up for what the user
        // perceives as one event; the summary carries no information the
        // individual notifications don't already have, so skip it.
        if (sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return

        val extras = sbn.notification.extras

        val title = extras.getString(Notification.EXTRA_TITLE, "") ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val body = if (bigText.isNotEmpty()) bigText else text
        if (title.isEmpty() && body.isEmpty()) return

        val contentFingerprint = "$title|$body"
        if (lastContentByKey[sbn.key] == contentFingerprint) return
        lastContentByKey[sbn.key] = contentFingerprint

        val payload = mapOf(
            "packageName" to packageName,
            "appName" to AppLabelResolver.resolveLabel(this, packageName),
            "title" to title,
            "text" to body,
            "timestamp" to sbn.postTime,
            "id" to sbn.key
        )

        MirrorLineChannel.channel?.invokeMethod("onNotification", payload)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val packageName = sbn.packageName ?: "unknown"
        if (packageName == this.packageName) return
        // Only clear the dedup cache so a future repost of the same key is
        // treated as fresh. We intentionally do NOT forward this event to
        // Dart anymore -- Android fires removals for many reasons (user
        // dismiss, source app auto-cancel, summary regrouping) that have
        // nothing to do with the user wanting the mirrored record gone.
        // Keeping the event in the DB matches how Call/SMS are persisted
        // regardless of the system notification's lifecycle (issue #59).
        lastContentByKey.remove(sbn.key)
    }
}

/** Resolves a package name to the app's user-facing label, e.g. "WhatsApp"
 *  instead of "com.whatsapp", so mirrored notifications read naturally. */
object AppLabelResolver {
    fun resolveLabel(context: android.content.Context, packageName: String): String {
        return try {
            val pm = context.packageManager
            val appInfo = pm.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            pm.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) {
            Log.w("MirrorLine", "Failed to resolve app label for $packageName: ${e.message}")
            packageName
        }
    }
}

/** Identifies the device's current default dialer/SMS apps, so their
 *  notifications can be excluded from generic mirroring (queried fresh each
 *  time rather than cached, since the user can change either default). */
object DefaultAppResolver {
    fun isDefaultDialerOrSms(context: android.content.Context, packageName: String): Boolean {
        return try {
            val telecomManager = context.getSystemService(android.telecom.TelecomManager::class.java)
            val defaultDialer = telecomManager?.defaultDialerPackage
            val defaultSms = android.provider.Telephony.Sms.getDefaultSmsPackage(context)
            packageName == defaultDialer || packageName == defaultSms
        } catch (e: Exception) {
            Log.w("MirrorLine", "Failed to resolve default dialer/SMS app: ${e.message}")
            false
        }
    }
}
