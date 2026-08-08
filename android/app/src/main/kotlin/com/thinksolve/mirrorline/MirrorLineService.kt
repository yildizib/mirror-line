package com.thinksolve.mirrorline

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
import android.telephony.SmsMessage
import android.telephony.TelephonyManager
import androidx.core.app.NotificationCompat
import com.thinksolve.mirrorline.MirrorLineService.Companion.RINGING_DEBOUNCE_MS
import com.thinksolve.mirrorline.MirrorLineService.Companion.SMS_DEBOUNCE_MS

class MirrorLineService : Service() {

    private var phoneStateReceiver: BroadcastReceiver? = null
    private var smsReceiver: BroadcastReceiver? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

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

    // Tracks the previous EXTRA_STATE so transitions can be classified
    // (e.g. RINGING -> IDLE means missed, OFFHOOK -> IDLE means the
    // answered call ended). Dart correlates these with the currently
    // "ringing" CallEvent itself -- native only reports the transition.
    private var lastCallState: String? = null

    // SMS parts for one logical (possibly multi-part) message can arrive
    // as several separate broadcasts in quick succession. Buffered per
    // sender and flushed as one notification after a short quiet period,
    // instead of each broadcast becoming its own mirrored message.
    private val smsHandler = Handler(Looper.getMainLooper())
    private val pendingSms = HashMap<String, PendingSms>()

    private data class PendingSms(var body: String, var contactName: String, val flush: Runnable)

    override fun onCreate() {
        super.onCreate()
        // Guarantee the shared Dart engine exists even if this service is
        // (re)started by the OS (START_STICKY) without any Activity ever
        // having launched in this process instance -- e.g. after the app's
        // process was killed and Android restarts the foreground service.
        MirrorLineEngine.getOrCreate(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        registerReceivers()
        acquireLocks()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        unregisterReceivers()
        releaseLocks()
        super.onDestroy()
    }

    /**
     * Foreground services are exempt from Doze's CPU/network deferral, but
     * that alone doesn't stop the Wi-Fi radio from dropping into a
     * power-save state once the screen turns off, which was causing the
     * TCP mirroring connection to drop shortly after the screen locks.
     * Holding a low-latency Wi-Fi lock plus a partial wake lock for as long
     * as this foreground service runs keeps the radio and CPU responsive
     * enough for the socket/heartbeat to survive screen-off. This does cost
     * extra battery -- an inherent trade-off for an app that must keep a
     * live, low-latency connection while the screen is off, which is why
     * the app also asks the user to exempt it from battery optimization.
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
            } catch (_: Exception) {
            }
        }

        if (wifiLock == null) {
            try {
                val wifiManager =
                    applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val lockType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    @Suppress("DEPRECATION")
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wifiManager.createWifiLock(lockType, "MirrorLine::WifiLock").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            } catch (_: Exception) {
            }
        }
    }

    private fun releaseLocks() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        wifiLock?.let { if (it.isHeld) it.release() }
        wifiLock = null
    }

    private fun invokeFlutter(method: String, arguments: Map<String, Any>) {
        try {
            MirrorLineChannel.channel?.invokeMethod(method, arguments)
        } catch (_: Exception) {
            // Flutter engine not available; event dropped.
        }
    }

    /**
     * The call-log entry for a just-finished call isn't guaranteed to be
     * written the instant IDLE fires -- some ROMs (observed on HyperOS) run
     * their own caller-ID/spam lookup before writing it, which can take well
     * over a second. A single short delay was missing the write entirely, so
     * this retries with growing delays (off the main thread) until a fresh
     * entry (see CallLogResolver's sinceMs bound) shows up or attempts run
     * out, then reports the (MISSED/ENDED) state change together with
     * whatever caller info was found. Dart's CallEvent merge (see
     * CallEvent.copyWith) only ever improves on what it already has -- an
     * empty result here is simply a no-op.
     */
    private fun enrichFromCallLogThenNotify(context: Context, state: String) {
        val mainHandler = Handler(Looper.getMainLooper())
        val callEndedAt = System.currentTimeMillis()
        Thread {
            var info: CallLogResolver.Entry? = null
            for (delayMs in CALL_LOG_RETRY_DELAYS_MS) {
                try {
                    Thread.sleep(delayMs)
                } catch (_: InterruptedException) {
                }
                info = CallLogResolver.latestEntry(context, sinceMs = callEndedAt)
                if (info != null) break
            }
            mainHandler.post {
                val args = mutableMapOf<String, Any>("state" to state)
                if (info != null) {
                    args["number"] = info.number
                    if (info.name.isNotEmpty()) args["contactName"] = info.name
                }
                invokeFlutter("onCall", args)
            }
        }.start()
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
    private fun startRingingDebounce(number: String, contactName: String) {
        cancelRingingDebounce()
        pendingRingingNumber = number
        pendingRingingContact = contactName
        val r = Runnable {
            pendingRinging = null
            invokeFlutter(
                "onCall",
                mapOf(
                    "number" to pendingRingingNumber,
                    "contactName" to pendingRingingContact,
                    "state" to "RINGING"
                )
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
    private fun feedRingingUpdate(number: String, contactName: String) {
        val empty = number.isBlank()
        if (empty && contactName.isBlank()) return
        val pending = pendingRinging
        if (pending != null) {
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
                "state" to "RINGING_UPDATE"
            )
        )
    }

    private fun cancelRingingDebounce() {
        pendingRinging?.let { callHandler.removeCallbacks(it) }
        pendingRinging = null
        pendingRingingNumber = ""
        pendingRingingContact = ""
    }

    /**
     * If the initial RINGING is still pending (debounce window not yet
     * elapsed), report it immediately and clear the pending state. Used
     * when a state transition (OFFHOOK/IDLE) arrives before the debounce
     * fired, so Dart has a ringing call to apply the transition to. No-op
     * if RINGING already went out.
     */
    private fun flushPendingRinging() {
        val r = pendingRinging ?: return
        callHandler.removeCallbacks(r)
        pendingRinging = null
        invokeFlutter(
            "onCall",
            mapOf(
                "number" to pendingRingingNumber,
                "contactName" to pendingRingingContact,
                "state" to "RINGING"
            )
        )
        pendingRingingNumber = ""
        pendingRingingContact = ""
    }

    private fun registerReceivers() {
        if (phoneStateReceiver == null) {
            phoneStateReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
                    val previous = lastCallState
                    lastCallState = state

                    when (state) {
                        TelephonyManager.EXTRA_STATE_RINGING -> {
                            val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
                                ?: ""
                            val contactName = ContactResolver.resolveName(context, number) ?: ""
                            // Android commonly re-broadcasts RINGING for the
                            // *same* call (often once without the number,
                            // then again with it a moment later). Only a
                            // transition INTO ringing is a genuinely new
                            // call; a repeat while already ringing is just
                            // an info update (e.g. the number finally
                            // resolved) for the call already being tracked.
                            val isNewCall = previous != TelephonyManager.EXTRA_STATE_RINGING
                            if (isNewCall) {
                                startRingingDebounce(number, contactName)
                            } else {
                                // A repeat RINGING for the already-tracked
                                // call. If this one carries a number and we
                                // haven't reported yet, fold it into the
                                // pending report so it goes out with it; if
                                // we already reported, treat it as the
                                // usual RINGING_UPDATE info merge.
                                feedRingingUpdate(number, contactName)
                            }
                        }
                        TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                            // A ringing call was just answered. (If we were
                            // already OFFHOOK, e.g. an outgoing call, this
                            // is a no-op event Dart ignores -- it only acts
                            // on this when it has a "ringing" call pending.)
                            if (previous == TelephonyManager.EXTRA_STATE_RINGING) {
                                // If the initial RINGING was still being
                                // debounced, flush it now so Dart has a
                                // ringing call to mark answered; otherwise
                                // the ANSWERED transition would be dropped.
                                flushPendingRinging()
                                invokeFlutter("onCall", mapOf("state" to "ANSWERED"))
                            }
                        }
                        TelephonyManager.EXTRA_STATE_IDLE -> {
                            // Same race as OFFHOOK: a missed call can go
                            // RINGING -> IDLE faster than the debounce
                            // window, so make sure Dart has seen RINGING
                            // before reporting the MISSED transition.
                            when (previous) {
                                TelephonyManager.EXTRA_STATE_RINGING -> {
                                    flushPendingRinging()
                                    enrichFromCallLogThenNotify(context, "MISSED")
                                }
                                TelephonyManager.EXTRA_STATE_OFFHOOK ->
                                    enrichFromCallLogThenNotify(context, "ENDED")
                            }
                        }
                    }
                }
            }
            val filter = IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
            registerExported(phoneStateReceiver!!, filter)
        }

        if (smsReceiver == null) {
            smsReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    val bundle = intent.extras ?: return
                    val pdus = bundle.get("pdus") as? Array<*> ?: return
                    val format = bundle.getString("format")
                    val messages = pdus.mapNotNull { pdu ->
                        (pdu as? ByteArray)?.let { SmsMessage.createFromPdu(it, format) }
                    }
                    if (messages.isEmpty()) return

                    messages
                        .groupBy { it.displayOriginatingAddress ?: it.originatingAddress ?: "" }
                        .forEach { (address, group) ->
                            val body = group.joinToString("") { it.messageBody ?: "" }
                            bufferSms(context, address, body)
                        }
                }
            }
            val filter = IntentFilter(android.provider.Telephony.Sms.Intents.SMS_RECEIVED_ACTION)
            filter.priority = 999
            registerExported(smsReceiver!!, filter)
        }

        registerCallStateListener()
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
                    val contactName = ContactResolver.resolveName(this@MirrorLineService, phoneNumber) ?: ""
                    feedRingingUpdate(phoneNumber, contactName)
                }
            }
            phoneStateListener = listener
            telephonyManager = tm
            tm.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
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

    /**
     * Multi-part (long) SMS, or a burst of quick separate texts from the
     * same sender, can arrive as several distinct broadcasts a few hundred
     * milliseconds apart. Coalesce same-sender broadcasts that land within
     * [SMS_DEBOUNCE_MS] of each other into a single mirrored message
     * instead of one per broadcast.
     */
    private fun bufferSms(context: Context, address: String, bodyPart: String) {
        val existing = pendingSms[address]
        if (existing != null) {
            smsHandler.removeCallbacks(existing.flush)
            existing.body += bodyPart
            smsHandler.postDelayed(existing.flush, SMS_DEBOUNCE_MS)
            return
        }

        lateinit var pending: PendingSms
        val flush = Runnable {
            pendingSms.remove(address)
            invokeFlutter(
                "onSms",
                mapOf(
                    "address" to address,
                    "contactName" to pending.contactName,
                    "body" to pending.body,
                    "threadId" to ""
                )
            )
        }
        pending = PendingSms(bodyPart, ContactResolver.resolveName(context, address) ?: "", flush)
        pendingSms[address] = pending
        smsHandler.postDelayed(flush, SMS_DEBOUNCE_MS)
    }

    private fun registerExported(receiver: BroadcastReceiver, filter: IntentFilter) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                registerReceiver(receiver, filter)
            }
        } catch (_: Exception) {
        }
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

        // Flush anything still buffered rather than silently dropping it,
        // then cancel so nothing fires after teardown.
        pendingSms.values.toList().forEach { smsHandler.removeCallbacks(it.flush) }
        pendingSms.values.toList().forEach { it.flush.run() }
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
        const val SMS_DEBOUNCE_MS = 700L
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
    }
}
