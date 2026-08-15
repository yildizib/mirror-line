package io.github.yildizib.mirrorline

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.app.NotificationCompat
import io.github.yildizib.mirrorline.MirrorLineService.Companion.RINGING_DEBOUNCE_MS
import java.util.concurrent.ExecutorService
import java.util.concurrent.Future
import java.util.concurrent.FutureTask
import java.util.concurrent.RejectedExecutionException

class MirrorLineService : Service() {

    private var phoneStateReceiver: BroadcastReceiver? = null
    private var smsReceiver: BroadcastReceiver? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    // Executor for CallLog enrichment thread pool (replaces raw Thread usage)
    private val callLogExecutor: ExecutorService = BoundedExecutors.single("mirrorline-telephony")
    private val callLogBaselineExecutor: ExecutorService =
        BoundedExecutors.single("mirrorline-call-baseline", capacity = 8)
    private val pendingCallLogTasks = mutableSetOf<Future<*>>()

    // Independent second source for the live incoming number, alongside
    // ACTION_PHONE_STATE_CHANGED below -- see registerCallStateListener.
    private var telephonyManager: TelephonyManager? = null
    private var phoneStateListener: PhoneStateListener? = null
    private var lastListenerNumber: String? = null

    // Debounce window for the initial RINGING of a new call. The very
    // first ACTION_PHONE_STATE_CHANGED broadcast often arrives with an
    // empty EXTRA_INCOMING_NUMBER (carrier timing, OEM call screening),
    // which used to fire call_incoming to the Main device with no number
    // and surface as "Bilinmeyen numara". Instead of reporting it
    // immediately, we hold the first RINGING for up to RINGING_DEBOUNCE_MS;
    // if a repeated broadcast or PhoneStateListener resolves the number
    // within that window, we report it with the number. If it doesn't,
    // we report it as-is (empty) and let the later callInfo/call-log
    // enrichment path backfill it -- same fallback as before.
    private val callHandler = Handler(Looper.getMainLooper())
    private var pendingRinging: Runnable? = null
    private var pendingRingingNumber: String = ""
    private var pendingRingingContact: String = ""
    private var pendingRingingSessionId: String? = null

    // Tracks the previous EXTRA_STATE so transitions can be classified
    // (e.g. RINGING -> IDLE means missed, OFFHOOK -> IDLE means the
    // answered call ended). Dart correlates these with the currently
    // "ringing" CallEvent itself -- native only reports the transition.
    private var lastCallState: String? = null
    private val callSessionFactory = CallSessionFactory()
    private var activeCallSession: CallSession? = null
    private val smsFingerprints = ExactFingerprintCache()
    private var receiverRegistrationAttempts = 0
    private val registrationHandler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!MirroringServiceController.isEligible(this)) {
            Watchdog.cancel(this)
            stopSelf(startId)
            return START_NOT_STICKY
        }
        ensureChannel()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        MirrorLineEngine.getOrCreate(this)
        registerReceivers()
        acquireLocks()

        Watchdog.schedule(this)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        unregisterReceivers()
        releaseLocks()

        // Cancel any in-flight CallLog enrichment tasks
        synchronized(pendingCallLogTasks) {
            pendingCallLogTasks.forEach { it.cancel(true) }
            pendingCallLogTasks.clear()
        }
        callLogExecutor.shutdownNow()
        callLogBaselineExecutor.shutdownNow()
        registrationHandler.removeCallbacksAndMessages(null)

        super.onDestroy()
    }

    /**
     * android:stopWithTask="false" (manifest) already tells the framework
     * not to stop this service when the task is swiped away from recents,
     * but some OEM ROMs (observed pattern on HyperOS/MIUI) don't fully
     * honor that and tear the process down anyway. As a fallback, restart
     * it immediately and synchronously -- not deferred through AlarmManager,
     * because by the time a delayed alarm fires the app is unambiguously
     * "in the background" and Android 12+ can refuse a startForegroundService
     * call at that point (ForegroundServiceStartNotAllowedException). Calling
     * it right here, while this service instance is still alive and already
     * running in the foreground, falls under Android's "app already has a
     * running foreground service" exemption, so it isn't subject to that
     * restriction. One-shot, triggered only when the task is actually
     * removed -- no recurring work, no extra battery cost.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        if (MirroringServiceController.isEligible(this)) {
            val result = MirroringServiceController.start(applicationContext)
            if (result.outcome == ServiceOutcome.FAILED) {
                Log.e("MirrorLine", "Failed to restart service from onTaskRemoved: ${result.error}")
            }
        } else {
            Watchdog.cancel(this)
        }
    }

    /**
     * Foreground services are exempt from Doze's CPU/network deferral, but
     * that alone doesn't stop the Wi-Fi radio from dropping into a
     * power-save state once the screen turns off, which was causing the
     * TCP mirroring connection to drop shortly after the screen locks.
     * Holding a high-perf Wi-Fi lock plus a partial wake lock for as long
     * as this foreground service runs keeps the radio and CPU responsive
     * enough for the 30s heartbeat / 90s receive-timeout socket to survive
     * screen-off, without pinning the radio at peak latency the way
     * WIFI_MODE_FULL_LOW_LATENCY did. This still costs extra battery --
     * an inherent trade-off for an app that must keep a live connection
     * while the screen is off, which is why the app also asks the user to
     * exempt it from battery optimization.
     */
    private fun acquireLocks() {
        if (wakeLock == null) {
            try {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = powerManager.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "MirrorLine::ConnectionWakeLock"
                ).apply {
                    setReferenceCounted(false)
                    acquire()
                }
            } catch (e: Exception) {
                Log.w("MirrorLine", "Failed to acquire wake lock: ${e.message}")
            }
        }

        if (wifiLock == null) {
            try {
                val wifiManager =
                    applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                // WIFI_MODE_FULL_LOW_LATENCY kept the radio at full power even
                // with the screen off, which was costing an outsized share of
                // battery for the benefit it gave. Now that the heartbeat
                // runs every 30s (see SocketManager._heartbeatInterval) and
                // the receive timeout is 90s, a standard high-perf Wi-Fi lock
                // is enough to keep the TCP connection alive through Doze --
                // the OS is still prevented from dropping the radio into its
                // deepest power-save, just not pinned at peak latency.
                val lockType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                } else {
                    @Suppress("DEPRECATION")
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wifiManager.createWifiLock(lockType, "MirrorLine::WifiLock").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            } catch (e: Exception) {
                Log.w("MirrorLine", "Failed to acquire Wi-Fi lock: ${e.message}")
            }
        }
    }

    private fun releaseLocks() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        wifiLock?.let { if (it.isHeld) it.release() }
        wifiLock = null
    }

    private fun invokeFlutter(
        method: String,
        arguments: Map<String, Any>,
        routerGeneration: Long? = null,
    ): Boolean {
        if (!MirroringServiceController.isEligible(this)) return false
        return if (routerGeneration == null) NativeEventRouter.route(method, arguments)
        else NativeEventRouter.routeIfCurrent(routerGeneration, method, arguments)
    }

    /**
     * The call-log entry for a just-finished call isn't guaranteed to be
     * written the instant IDLE fires -- some ROMs (observed on HyperOS) run
     * their own caller-ID/spam lookup before writing it, which can take well
     * over a second. A single short delay was missing the write entirely, so
     * this retries with growing delays (off the executor thread) until a fresh
     * entry (see CallLogResolver's sinceMs bound) shows up or attempts run
     * out, then reports the (MISSED/ENDED) state change together with
     * whatever caller info was found. Dart's CallEvent merge (see
     * CallEvent.copyWith) only ever improves on what it already has -- an
     * empty result here is simply a no-op.
     */
    private fun enrichFromCallLogThenNotify(
        context: Context,
        state: String,
        window: CallWindow,
        session: CallSession,
    ) {
        val mainHandler = Handler(Looper.getMainLooper())
        val routerGeneration = session.lifecycleGeneration
        val work = Runnable {
            try {
                window.baseline.await(CALL_LOG_BASELINE_WAIT_MS)
                var info: CallLogResolver.Entry? = null
                for (delayMs in CALL_LOG_RETRY_DELAYS_MS) {
                    if (Thread.currentThread().isInterrupted) {
                        Log.w("MirrorLine", "CallLog enrichment interrupted")
                        return@Runnable
                    }
                    try {
                        Thread.sleep(delayMs)
                    } catch (_: InterruptedException) {
                        Thread.currentThread().interrupt()
                        return@Runnable
                    }
                    info = CallLogResolver.matchingEntry(context, window)
                    if (info != null) break
                }
                mainHandler.post {
                    if (!MirroringServiceController.isEligible(this)) return@post
                    val args = mutableMapOf<String, Any>(
                        "state" to state,
                        "callSessionId" to session.id,
                    )
                    if (info != null) {
                        args["number"] = info.number
                        if (info.name.isNotEmpty()) args["contactName"] = info.name
                    }
                    invokeFlutter("onCall", args, routerGeneration)
                }
            } catch (e: Exception) {
                Log.e("MirrorLine", "CallLog enrichment failed: ${e.message}", e)
            }
        }
        val task = object : FutureTask<Unit>(work, Unit) {
            override fun done() {
                synchronized(pendingCallLogTasks) { pendingCallLogTasks.remove(this) }
            }
        }
        synchronized(pendingCallLogTasks) {
            pendingCallLogTasks.add(task)
        }
        try {
            callLogExecutor.execute(task)
        } catch (_: RejectedExecutionException) {
            synchronized(pendingCallLogTasks) { pendingCallLogTasks.remove(task) }
            emitTerminalCall(state, session, routerGeneration)
        }
    }

    private fun emitTerminalCall(
        state: String,
        session: CallSession,
        routerGeneration: Long? = session.lifecycleGeneration,
    ) {
        invokeFlutter(
            "onCall",
            mapOf("state" to state, "callSessionId" to session.id),
            routerGeneration,
        )
    }

    private fun captureCallLogBaseline(
        context: Context,
        session: CallSession,
        attempt: Int = 0,
    ) {
        if (session.callLogBaseline.snapshot().resolved) return
        if (!MirroringServiceController.isEligible(this) ||
            !NativeEventRouter.isGenerationCurrent(session.lifecycleGeneration)
        ) return

        val retry = {
            if (attempt < CALL_LOG_BASELINE_RETRY_COUNT) {
                registrationHandler.postDelayed(
                    { captureCallLogBaseline(context, session, attempt + 1) },
                    CALL_LOG_BASELINE_RETRY_DELAY_MS,
                )
            }
        }
        try {
            callLogBaselineExecutor.execute {
                val result = CallLogResolver.captureBaseline(context)
                if (result.successful &&
                    MirroringServiceController.isEligible(this) &&
                    NativeEventRouter.isGenerationCurrent(session.lifecycleGeneration)
                ) {
                    session.callLogBaseline.resolve(result.rowId)
                } else {
                    retry()
                }
            }
        } catch (_: RejectedExecutionException) {
            retry()
        }
    }

    /**
     * Holds the first RINGING of a new call for [RINGING_DEBOUNCE_MS] before
     * reporting it, so a late-arriving incoming number (from a repeated
     * RINGING broadcast or PhoneStateListener) can be folded in and the
     * Main device's notification shows the actual number instead of
     * "Bilinmeyen numara". If no number arrives within the window, the
     * call is reported as-is and the existing callInfo/call-log
     * enrichment path still backfills it later.
     */
    private fun startRingingDebounce(
        number: String,
        contactName: String,
        session: CallSession,
    ) {
        cancelRingingDebounce()
        pendingRingingNumber = number
        pendingRingingContact = contactName
        pendingRingingSessionId = session.id
        val routerGeneration = session.lifecycleGeneration
        val r = Runnable {
            if (activeCallSession?.id != session.id) return@Runnable
            pendingRinging = null
            invokeFlutter(
                "onCall",
                mapOf(
                    "number" to pendingRingingNumber,
                    "contactName" to pendingRingingContact,
                    "state" to "RINGING",
                    "callSessionId" to session.id,
                ),
                routerGeneration,
            )
        }
        pendingRinging = r
        callHandler.postDelayed(r, RINGING_DEBOUNCE_MS)
    }

    /**
     * A later source (repeated RINGING broadcast or PhoneStateListener)
     * resolved the number for the call currently being held. If we
     * haven't reported yet, fold it into the pending report so it goes
     * out with it; if we already reported, emit a RINGING_UPDATE so Dart
     * merges it into the tracked call as before.
     */
    private fun feedRingingUpdate(
        number: String,
        contactName: String,
        session: CallSession,
        routerGeneration: Long? = session.lifecycleGeneration,
    ) {
        if (activeCallSession?.id != session.id) return
        val empty = number.isBlank()
        if (empty && contactName.isBlank()) return
        val pending = pendingRinging
        if (pending != null && pendingRingingSessionId == session.id) {
            if (number.isNotBlank()) pendingRingingNumber = number
            if (contactName.isNotBlank()) pendingRingingContact = contactName
            return
        }
        // Already reported -- behave like the old RINGING_UPDATE path.
        invokeFlutter(
            "onCall",
            mapOf(
                "number" to number,
                "contactName" to contactName,
                "state" to "RINGING_UPDATE",
                "callSessionId" to session.id,
            ),
            routerGeneration,
        )
    }

    private fun cancelRingingDebounce() {
        pendingRinging?.let { callHandler.removeCallbacks(it) }
        pendingRinging = null
        pendingRingingNumber = ""
        pendingRingingContact = ""
        pendingRingingSessionId = null
    }

    /**
     * If the initial RINGING is still pending (debounce window not yet
     * elapsed), report it immediately and clear the pending state. Used
     * when a state transition (OFFHOOK/IDLE) arrives before the debounce
     * fired, so Dart has a ringing call to apply the transition to. No-op
     * if RINGING already went out.
     */
    private fun flushPendingRinging(session: CallSession) {
        if (pendingRingingSessionId != session.id) return
        val r = pendingRinging ?: return
        callHandler.removeCallbacks(r)
        pendingRinging = null
        invokeFlutter(
            "onCall",
            mapOf(
                "number" to pendingRingingNumber,
                "contactName" to pendingRingingContact,
                "state" to "RINGING",
                "callSessionId" to session.id,
            ),
            session.lifecycleGeneration,
        )
        pendingRingingNumber = ""
        pendingRingingContact = ""
        pendingRingingSessionId = null
    }

    private fun registerReceivers() {
        if (phoneStateReceiver == null) {
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
                    val previous = lastCallState
                    lastCallState = state

                    when (state) {
                        TelephonyManager.EXTRA_STATE_RINGING -> {
                            if (previous != TelephonyManager.EXTRA_STATE_RINGING) {
                                activeCallSession = callSessionFactory.create(
                                    System.currentTimeMillis(),
                                    CallDirection.INCOMING,
                                    NativeEventRouter.generation(),
                                )
                                captureCallLogBaseline(context, activeCallSession!!)
                            }
                            val session = activeCallSession ?: return
                            val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
                                ?: ""
                            // Android commonly re-broadcasts RINGING for the
                            // *same* call (often once without the number,
                            // then again with it a moment later). Only a
                            // transition INTO ringing is a genuinely new
                            // call; a repeat while already ringing is just
                            // an info update (e.g. the number finally
                            // resolved) for the call already being tracked.
                            val isNewCall = previous != TelephonyManager.EXTRA_STATE_RINGING
                            if (isNewCall) startRingingDebounce(number, "", session)
                            else feedRingingUpdate(number, "", session)
                            try {
                                val routerGeneration = session.lifecycleGeneration
                                callLogExecutor.execute {
                                    val contactName = ContactResolver.resolveName(context, number) ?: ""
                                    callHandler.post {
                                        if (MirroringServiceController.isEligible(
                                                this@MirrorLineService,
                                            )
                                        ) {
                                            feedRingingUpdate(
                                                number,
                                                contactName,
                                                session,
                                                routerGeneration,
                                            )
                                        }
                                    }
                                }
                            } catch (_: RejectedExecutionException) {
                                // The number-bearing ringing event was already retained.
                            }
                        }
                        TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                            if (activeCallSession == null) {
                                activeCallSession = callSessionFactory.create(
                                    System.currentTimeMillis(),
                                    CallDirection.OUTGOING,
                                    NativeEventRouter.generation(),
                                )
                                captureCallLogBaseline(context, activeCallSession!!)
                            }
                            val session = activeCallSession ?: return
                            // A ringing call was just answered. (If we were
                            // already OFFHOOK, e.g. an outgoing call, this
                            // is a no-op event Dart ignores -- it only acts
                            // on this when it has a "ringing" call pending.)
                            if (previous == TelephonyManager.EXTRA_STATE_RINGING) {
                                // If the initial RINGING was still being
                                // debounced, flush it now so Dart has a
                                // ringing call to mark answered; otherwise
                                // the ANSWERED transition would be dropped.
                                flushPendingRinging(session)
                                invokeFlutter(
                                    "onCall",
                                    mapOf(
                                        "state" to "ANSWERED",
                                        "callSessionId" to session.id,
                                    ),
                                    session.lifecycleGeneration,
                                )
                            }
                        }
                        TelephonyManager.EXTRA_STATE_IDLE -> {
                            val session = activeCallSession ?: return
                            val endedAt = System.currentTimeMillis()
                            val window = CallWindow(
                                session.startedAtMs,
                                endedAt,
                                session.direction,
                                session.callLogBaseline,
                            )
                            // Same race as OFFHOOK: a missed call can go
                            // RINGING -> IDLE faster than the debounce
                            // window, so make sure Dart has seen RINGING
                            // before reporting the MISSED transition.
                            when (previous) {
                                TelephonyManager.EXTRA_STATE_RINGING -> {
                                    flushPendingRinging(session)
                                    enrichFromCallLogThenNotify(
                                        context,
                                        "MISSED",
                                        window,
                                        session,
                                    )
                                }
                                TelephonyManager.EXTRA_STATE_OFFHOOK ->
                                    enrichFromCallLogThenNotify(
                                        context,
                                        "ENDED",
                                        window,
                                        session,
                                    )
                            }
                            activeCallSession = null
                        }
                    }
                }
            }
            val filter = IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
            if (registerExported(receiver, filter)) phoneStateReceiver = receiver
        }

        if (smsReceiver == null) {
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    val parts = android.provider.Telephony.Sms.Intents
                        .getMessagesFromIntent(intent)
                        .map {
                            SmsPart(
                                it.displayOriginatingAddress ?: it.originatingAddress ?: "",
                                it.messageBody ?: "",
                                it.timestampMillis,
                            )
                        }
                    SmsAssembler.assemble(parts).forEach { sms ->
                        if (!smsFingerprints.addIfNew(sms.fingerprint)) return@forEach
                        val routerGeneration = NativeEventRouter.generation()
                        try {
                            callLogExecutor.execute {
                                val contactName = ContactResolver.resolveName(context, sms.address) ?: ""
                                emitSms(sms, contactName, routerGeneration)
                            }
                        } catch (_: RejectedExecutionException) {
                            emitSms(sms, "", routerGeneration)
                        }
                    }
                }
            }
            val filter = IntentFilter(android.provider.Telephony.Sms.Intents.SMS_RECEIVED_ACTION)
            filter.priority = 999
            if (registerExported(receiver, filter)) smsReceiver = receiver
        }

        registerCallStateListener()
        if ((phoneStateReceiver == null || smsReceiver == null || phoneStateListener == null) &&
            MirroringServiceController.isEligible(this) && receiverRegistrationAttempts++ < 3
        ) {
            registrationHandler.postDelayed({ registerReceivers() }, 1_000L)
        } else if (phoneStateReceiver != null && smsReceiver != null && phoneStateListener != null) {
            receiverRegistrationAttempts = 0
        }
    }

    /**
     * ACTION_PHONE_STATE_CHANGED's EXTRA_INCOMING_NUMBER can come back
     * empty on *every* broadcast for a given call on some ROMs (observed on
     * HyperOS) even though the number resolves moments later -- Android's
     * own Phone app shows it correctly because it isn't relying on that
     * broadcast alone. PhoneStateListener.onCallStateChanged's deprecated
     * phoneNumber overload is a second, independently-delivered read of the
     * same telephony state (still functional despite the class being
     * deprecated in API 31 -- its replacement, TelephonyCallback, dropped
     * the phone number parameter entirely for privacy, so this remains the
     * only public API that provides it at all). When it resolves a number
     * the broadcast missed, it's reported the same way the broadcast's own
     * RINGING_UPDATE case is: Dart's CallEventHandler already merges it
     * into whichever call is currently tracked as ringing.
     */
    @Suppress("DEPRECATION")
    private fun registerCallStateListener() {
        if (phoneStateListener != null) return
        try {
            val tm = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager ?: return
            val listener = object : PhoneStateListener() {
                @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
                override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                    if (state == TelephonyManager.CALL_STATE_IDLE) {
                        lastListenerNumber = null
                        return
                    }
                    if (state != TelephonyManager.CALL_STATE_RINGING) return
                    if (phoneNumber.isNullOrEmpty() || phoneNumber == lastListenerNumber) return
                    lastListenerNumber = phoneNumber
                    val session = activeCallSession ?: return
                    feedRingingUpdate(phoneNumber, "", session)
                    val routerGeneration = NativeEventRouter.generation()
                    try {
                        callLogExecutor.execute {
                            val contactName = ContactResolver.resolveName(
                                this@MirrorLineService,
                                phoneNumber,
                            ) ?: ""
                            callHandler.post {
                                if (MirroringServiceController.isEligible(
                                        this@MirrorLineService,
                                    )
                                ) {
                                    feedRingingUpdate(
                                        phoneNumber,
                                        contactName,
                                        session,
                                        routerGeneration,
                                    )
                                }
                            }
                        }
                    } catch (_: RejectedExecutionException) {
                        // The number-bearing update was already emitted.
                    }
                }
            }
            tm.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
            phoneStateListener = listener
            telephonyManager = tm
        } catch (_: Exception) {
        }
    }

    @Suppress("DEPRECATION")
    private fun unregisterCallStateListener() {
        phoneStateListener?.let { listener ->
            try {
                telephonyManager?.listen(listener, PhoneStateListener.LISTEN_NONE)
            } catch (_: Exception) {
            }
        }
        phoneStateListener = null
        telephonyManager = null
        lastListenerNumber = null
    }

    private fun registerExported(receiver: BroadcastReceiver, filter: IntentFilter): Boolean =
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                registerReceiver(receiver, filter)
            }
            true
        } catch (_: Exception) {
            false
        }

    private fun emitSms(
        sms: AssembledSms,
        contactName: String,
        routerGeneration: Long,
    ) {
        val routed = invokeFlutter(
            "onSms",
            mapOf(
                "address" to sms.address,
                "contactName" to contactName,
                "body" to sms.body,
                "threadId" to "",
            ),
            routerGeneration,
        )
        if (!routed) smsFingerprints.remove(sms.fingerprint)
    }

    private fun unregisterReceivers() {
        phoneStateReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
            }
        }
        phoneStateReceiver = null

        smsReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
            }
        }
        smsReceiver = null

        unregisterCallStateListener()

        // Cancel any held RINGING so it doesn't fire after teardown. We
        // don't flush it -- if the call is still ringing at shutdown, the
        // next process restart (START_STICKY) will re-register and the
        // ongoing call's later transitions will be reported then.
        cancelRingingDebounce()

    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "MirrorLine Senkronizasyon",
                    NotificationManager.IMPORTANCE_LOW
                )
                channel.description = "Arama ve SMS senkronizasyonu arka plan servisi"
                manager.createNotificationChannel(channel)
            }
        }
    }

    private fun buildNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MirrorLine çalışıyor")
            .setContentText("Arama ve SMS senkronizasyonu aktif")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setOngoing(true)
            .setSilent(true)
            .build()

    companion object {
        const val CHANNEL_ID = "mirrorline_service"
        const val NOTIFICATION_ID = 10001
        // How long to wait for the incoming number to resolve on the
        // first RINGING broadcast before giving up and reporting the call
        // with whatever (possibly empty) number we have. ~500ms is enough
        // to catch the second RINGING broadcast / a PhoneStateListener
        // callback on most ROMs without making the Main device's call
        // notification feel delayed.
        const val RINGING_DEBOUNCE_MS = 500L
        // Cumulative ~2s across up to 3 attempts -- enough slack for a ROM's
        // own caller-ID/spam lookup to finish writing the call-log entry.
        val CALL_LOG_RETRY_DELAYS_MS = longArrayOf(400L, 600L, 1000L)
        const val CALL_LOG_BASELINE_RETRY_COUNT = 3
        const val CALL_LOG_BASELINE_RETRY_DELAY_MS = 100L
        const val CALL_LOG_BASELINE_WAIT_MS = 500L
    }
}
