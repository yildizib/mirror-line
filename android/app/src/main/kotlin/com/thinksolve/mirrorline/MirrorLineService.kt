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
import android.telephony.SmsMessage
import android.telephony.TelephonyManager
import androidx.core.app.NotificationCompat

class MirrorLineService : Service() {

    private var phoneStateReceiver: BroadcastReceiver? = null
    private var smsReceiver: BroadcastReceiver? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

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
                                ?: "unknown"
                            val contactName = ContactResolver.resolveName(context, number) ?: ""
                            // Android commonly re-broadcasts RINGING for the
                            // *same* call (often once without the number,
                            // then again with it a moment later). Only a
                            // transition INTO ringing is a genuinely new
                            // call; a repeat while already ringing is just
                            // an info update (e.g. the number finally
                            // resolved) for the call already being tracked.
                            val isNewCall = previous != TelephonyManager.EXTRA_STATE_RINGING
                            invokeFlutter(
                                "onCall",
                                mapOf(
                                    "number" to number,
                                    "contactName" to contactName,
                                    "state" to if (isNewCall) "RINGING" else "RINGING_UPDATE"
                                )
                            )
                        }
                        TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                            // A ringing call was just answered. (If we were
                            // already OFFHOOK, e.g. an outgoing call, this
                            // is a no-op event Dart ignores -- it only acts
                            // on this when it has a "ringing" call pending.)
                            if (previous == TelephonyManager.EXTRA_STATE_RINGING) {
                                invokeFlutter("onCall", mapOf("state" to "ANSWERED"))
                            }
                        }
                        TelephonyManager.EXTRA_STATE_IDLE -> {
                            when (previous) {
                                TelephonyManager.EXTRA_STATE_RINGING ->
                                    invokeFlutter("onCall", mapOf("state" to "MISSED"))
                                TelephonyManager.EXTRA_STATE_OFFHOOK ->
                                    invokeFlutter("onCall", mapOf("state" to "ENDED"))
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
                        .groupBy { it.displayOriginatingAddress ?: it.originatingAddress ?: "unknown" }
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
    }
}
