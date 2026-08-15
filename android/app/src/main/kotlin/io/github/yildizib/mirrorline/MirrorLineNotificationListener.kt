package io.github.yildizib.mirrorline

import android.app.Notification
import android.content.pm.PackageManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import android.content.ComponentName
import android.os.Handler
import android.os.Looper
import java.util.concurrent.RejectedExecutionException
import java.lang.ref.WeakReference

class MirrorLineNotificationListener : NotificationListenerService() {

    // Android reposts the *same* logical notification repeatedly (preview
    // text tweaks, summary + child updates, etc.), each time with a fresh
    // postTime. Keying purely off postTime (the old behaviour) meant every
    // repost became a brand-new mirrored notification on the other phone.
    // sbn.key stays stable for the life of one logical notification, and
    // remembering the last content sent per key lets identical reposts be
    // skipped instead of duplicated.
    private val lastContentByKey = HashMap<String, String>()
    private val resolverExecutor = BoundedExecutors.single("mirrorline-notifications")
    private val drainRetryHandler = Handler(Looper.getMainLooper())
    private val pendingNotifications = KeyedDrainQueue<String, PendingNotification>()
    private val drainLock = Any()
    private var drainState = DrainState.IDLE
    private var rebindAttempts = 0
    private var destroyed = false
    private data class PendingNotification(
        val sbn: StatusBarNotification,
        val packageName: String,
        val routerGeneration: Long,
    )

    private enum class DrainState { IDLE, SUBMITTED, RUNNING, RETRY_WAIT }
    private val rebindRunnable = object : Runnable {
        override fun run() {
            if (destroyed || !MirroringServiceController.isEligible(this@MirrorLineNotificationListener)) {
                cancelRebind()
                return
            }
            if (rebindAttempts >= MAX_REBIND_ATTEMPTS) return
            rebindAttempts++
            try {
                requestRebind(
                    ComponentName(
                        this@MirrorLineNotificationListener,
                        MirrorLineNotificationListener::class.java,
                    ),
                )
            } catch (_: Exception) {
            }
            if (rebindAttempts < MAX_REBIND_ATTEMPTS) {
                mainHandler.postDelayed(this, REBIND_DELAY_MS)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        activeInstance = WeakReference(this)
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        cancelRebind()
        if (MirroringServiceController.isEligible(this)) {
            MirroringServiceController.start(this)
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        scheduleRebind()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        if (!MirroringServiceController.isEligible(this)) {
            cancelRebind()
            clearPendingNotificationsInternal()
            Watchdog.cancel(this)
            return
        }
        val packageName = sbn.packageName ?: "unknown"
        if (packageName == this.packageName) return
        val routerGeneration = NativeEventRouter.generation()

        enqueueNotification(PendingNotification(sbn, packageName, routerGeneration))
    }

    private fun enqueueNotification(notification: PendingNotification) {
        val shouldSubmit = synchronized(drainLock) {
            pendingNotifications.put(notification.sbn.key, notification)
            if (drainState == DrainState.IDLE) {
                drainState = DrainState.SUBMITTED
                true
            } else {
                false
            }
        }
        if (shouldSubmit) submitDrain()
    }

    private fun submitDrain() {
        try {
            resolverExecutor.execute(::drainNotifications)
        } catch (_: RejectedExecutionException) {
            synchronized(drainLock) { drainState = DrainState.RETRY_WAIT }
            drainRetryHandler.postDelayed(
                {
                    if (destroyed || !MirroringServiceController.isEligible(this)) {
                        clearPendingNotificationsInternal()
                    } else {
                        synchronized(drainLock) { drainState = DrainState.SUBMITTED }
                        submitDrain()
                    }
                },
                DRAIN_RETRY_DELAY_MS,
            )
        }
    }

    private fun drainNotifications() {
        synchronized(drainLock) { drainState = DrainState.RUNNING }
        while (true) {
            if (destroyed || !MirroringServiceController.isEligible(this)) {
                clearPendingNotificationsInternal()
                synchronized(drainLock) { drainState = DrainState.IDLE }
                return
            }
            val pending = synchronized(drainLock) {
                val next = pendingNotifications.poll()
                if (next == null) drainState = DrainState.IDLE
                next
            } ?: return
            if (NativeEventRouter.isGenerationCurrent(pending.routerGeneration)) {
                processNotification(
                    pending.sbn,
                    pending.packageName,
                    pending.routerGeneration,
                )
            }
        }
    }

    private fun clearPendingNotificationsInternal() {
        drainRetryHandler.removeCallbacksAndMessages(null)
        synchronized(drainLock) {
            pendingNotifications.clear()
            if (drainState == DrainState.RETRY_WAIT) drainState = DrainState.IDLE
        }
    }

    private fun processNotification(
        sbn: StatusBarNotification,
        packageName: String,
        routerGeneration: Long,
    ) {
        if (!MirroringServiceController.isEligible(this)) return

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
        synchronized(lastContentByKey) {
            if (lastContentByKey[sbn.key] == contentFingerprint) return
        }

        val payload = mapOf(
            "packageName" to packageName,
            "appName" to AppLabelResolver.resolveLabel(this, packageName),
            "title" to title,
            "text" to body,
            "timestamp" to sbn.postTime,
            "id" to sbn.key
        )

        // Queue before startup so a listener-first cold process cannot lose
        // the notification while Flutter is being initialized.
        if (MirroringServiceController.isEligible(this)) {
            val routed = NativeEventRouter.routeIfCurrent(
                routerGeneration,
                "onNotification",
                payload,
            )
            if (routed) {
                synchronized(lastContentByKey) {
                    lastContentByKey[sbn.key] = contentFingerprint
                }
                MirroringServiceController.start(this)
            }
        }
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
        try {
            resolverExecutor.execute {
                synchronized(lastContentByKey) { lastContentByKey.remove(sbn.key) }
            }
        } catch (_: RejectedExecutionException) {
            synchronized(lastContentByKey) { lastContentByKey.remove(sbn.key) }
        }
    }

    override fun onDestroy() {
        destroyed = true
        cancelRebind()
        clearPendingNotificationsInternal()
        if (activeInstance?.get() === this) activeInstance = null
        resolverExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun scheduleRebind() {
        cancelRebind()
        if (!destroyed && MirroringServiceController.isEligible(this)) {
            mainHandler.postDelayed(rebindRunnable, REBIND_DELAY_MS)
        }
    }

    private fun cancelRebind() {
        mainHandler.removeCallbacks(rebindRunnable)
        rebindAttempts = 0
    }

    companion object {
        private const val MAX_REBIND_ATTEMPTS = 3
        private const val REBIND_DELAY_MS = 1_000L
        private const val DRAIN_RETRY_DELAY_MS = 100L
        private val mainHandler = Handler(Looper.getMainLooper())
        private var activeInstance: WeakReference<MirrorLineNotificationListener>? = null

        fun cancelPendingRebind() {
            activeInstance?.get()?.cancelRebind()
        }

        fun clearPendingNotifications() {
            activeInstance?.get()?.clearPendingNotificationsInternal()
        }
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
