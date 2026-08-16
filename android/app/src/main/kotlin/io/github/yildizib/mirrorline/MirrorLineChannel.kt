package io.github.yildizib.mirrorline

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.IntentFilter
import android.app.PendingIntent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telecom.TelecomManager
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import java.net.Inet4Address
import java.util.concurrent.ExecutorService
import java.util.concurrent.RejectedExecutionException

/**
 * Owns the "io.github.yildizib.mirrorline/telephony" MethodChannel and its
 * handler, wired to the shared engine (see MirrorLineEngine) instead of to
 * any single Activity instance.
 *
 * Previously this lived entirely inside MainActivity, which meant native
 * call/SMS events (and Dart's ability to start/stop the foreground
 * service) silently stopped working whenever the process was restarted
 * without the user reopening the app -- e.g. Android restarting a killed
 * foreground service via START_STICKY. Almost everything here only needs
 * a Context, not a live Activity; the one exception (requesting runtime
 * permissions) is routed through whichever MainActivity is currently
 * resumed, if any.
 */
object MirrorLineChannel {
    const val CHANNEL_NAME = "io.github.yildizib.mirrorline/telephony"
    const val TELEPHONY_PERMISSIONS_REQUEST_CODE = 1001

    var channel: MethodChannel? = null
        private set

    private var activityRef: WeakReference<MainActivity>? = null

    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var lastReportedIp: String? = null
    // Set when the default network is lost (e.g. an AP roam with a brief
    // full disconnect, or a router reboot on the same subnet). Lets the
    // next "back online" check report a change even if the IP came back
    // identical -- without this the Dart side would wait out the full 90s
    // heartbeat timeout before re-discovering the peer, the "2 minutes of
    // silence" this callback exists to avoid.
    private var wasOffline = false
    private val networkHandler = Handler(Looper.getMainLooper())
    private var pendingNetworkChange: Runnable? = null
    private val resolverExecutor: ExecutorService = BoundedExecutors.single("mirrorline-resolvers")
    private var networkRegistrationAttempts = 0
    private var pendingNetworkRetry: Runnable? = null

    // Android can fire several onLinkPropertiesChanged callbacks in quick
    // succession for one real network transition (address assigned, then
    // DNS servers updated, etc.) -- this coalesces them into one Dart event.
    private const val NETWORK_CHANGE_DEBOUNCE_MS = 300L

    private val requiredPermissions = buildList {
        add(Manifest.permission.READ_PHONE_STATE)
        add(Manifest.permission.READ_CALL_LOG)
        add(Manifest.permission.ANSWER_PHONE_CALLS)
        add(Manifest.permission.RECEIVE_SMS)
        add(Manifest.permission.SEND_SMS)
    }.toTypedArray()

    // Requested alongside the required ones (one combined system dialog),
    // but never gates hasAllPermissions()/startMirrorService(): contact
    // name resolution (see ContactResolver) is a nice-to-have, not
    // required for call/SMS mirroring to work.
    private val optionalPermissions = arrayOf(Manifest.permission.READ_CONTACTS)

    fun setActivity(activity: MainActivity?) {
        activityRef = if (activity != null) WeakReference(activity) else null
    }

    fun attach(context: Context, engine: FlutterEngine) {
        if (channel != null) return
        val appContext = context.applicationContext
        val methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        channel = methodChannel
        NativeEventRouter.attach(methodChannel)

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening", "startService" -> {
                    result.success(ensureAndStart(appContext).toMap())
                }
                "stopListening", "stopService" -> {
                    val current = MirroringLifecycleStore(appContext).read()
                    val synced = MirroringLifecycleState(
                        initialized = true,
                        enabled = call.argument<Boolean>("enabled") ?: false,
                        role = call.argument<String>("role") ?: current.role,
                        paired = call.argument<Boolean>("paired") ?: current.paired,
                    )
                    val serviceResult = MirroringServiceController.stop(appContext, synced)
                    reconcileNetworkMonitoring(appContext)
                    result.success(serviceResult.toMap())
                }
                "syncMirroringEligibility" -> {
                    val state = MirroringLifecycleStore(appContext).sync(
                        enabled = call.argument<Boolean>("enabled") ?: false,
                        role = call.argument<String>("role") ?: "",
                        paired = call.argument<Boolean>("paired") ?: false,
                    )
                    val eligible = MirroringLifecyclePolicy.isEligible(
                        state,
                        hasAllPermissions(appContext),
                    )
                    val networkEligible = MirroringLifecyclePolicy.shouldMonitorNetwork(state)
                    reconcileNetworkMonitoring(appContext)
                    if (!eligible) {
                        MirroringServiceController.stop(
                            appContext,
                            clearNativeEvents = !networkEligible,
                        )
                    }
                    result.success(state.toMap(hasAllPermissions(appContext), eligible))
                }
                "getMirroringLifecycle" -> {
                    val (state, permissions) = MirroringServiceController.lifecycle(appContext)
                    result.success(
                        state.toMap(
                            permissions,
                            MirroringLifecyclePolicy.isEligible(state, permissions),
                        ),
                    )
                }
                "nativeEventsReady" -> {
                    NativeEventRouter.ready()
                    result.success(null)
                }
                "nativeEventsNotReady", "notReady" -> {
                    NativeEventRouter.notReady()
                    MirrorLineNotificationListener.clearPendingNotifications()
                    result.success(null)
                }
                "rejectCall" -> result.success(rejectCall(appContext))
                "sendSms" -> {
                    val address = call.argument<String>("address") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    val operationId = call.argument<String>("operationId") ?: ""
                    try {
                        sendSms(appContext, address, body, operationId)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SMS_SEND_FAILED", e.message, null)
                    }
                }
                "getLocalIp" -> runResolver(result) { getLocalIp(appContext) }
                "isNotificationListenerEnabled" -> result.success(isNotificationListenerEnabled(appContext))
                "openNotificationListenerSettings" -> {
                    openNotificationListenerSettings(appContext)
                    result.success(null)
                }
                "hasKnownAutoStartSettings" -> result.success(OemAutoStart.hasKnownScreen())
                "openAutoStartSettings" -> {
                    OemAutoStart.open(appContext)
                    result.success(null)
                }
                "hasKnownBatterySaverSettings" -> result.success(OemAutoStart.hasKnownBatterySaverScreen())
                "openBatterySaverSettings" -> {
                    OemAutoStart.openBatterySaver(appContext)
                    result.success(null)
                }
                "resolveContactName" -> {
                    val number = call.argument<String>("number") ?: ""
                    runResolver(result) { ContactResolver.resolveName(appContext, number) }
                }
                "getInstalledApps" -> runResolver(result) { InstalledAppsResolver.list(appContext) }
                "getAppIcon" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    runResolver(result) { InstalledAppsResolver.iconBytes(appContext, packageName) }
                }
                else -> result.notImplemented()
            }
        }

        reconcileNetworkMonitoring(appContext)
    }

    /**
     * Detects network changes that connectivity-type monitoring on the Dart
     * side (see ConnectivityService) can't see -- e.g. roaming from one WiFi
     * network to another, where the transport stays "wifi" throughout but
     * the IP/subnet changes. onLinkPropertiesChanged fires on exactly that.
     *
     * Registered once, role-agnostically, from attach() rather than tied to
     * MirrorLineService's lifecycle: that service only ever runs on the
     * 'source' device, but it's 'main' that dials out and most needs to
     * react quickly to having roamed (see ConnectionNotifier._maybeRunFallbackScan,
     * "only Main ever dials out"). attach() runs for both roles whenever the
     * shared, process-lifetime FlutterEngine is created, and -- like the
     * channel itself -- is never torn down for the life of the process, so
     * the callback's lifetime matches.
     */
    fun reconcileNetworkMonitoring(context: Context) {
        val state = MirroringLifecycleStore(context).read()
        if (MirroringLifecyclePolicy.shouldMonitorNetwork(state)) {
            registerNetworkCallback(context.applicationContext)
        } else {
            unregisterNetworkCallback()
        }
    }

    private fun registerNetworkCallback(context: Context) {
        if (networkCallback != null) return
        val state = MirroringLifecycleStore(context).read()
        if (!MirroringLifecyclePolicy.shouldMonitorNetwork(state)) return
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
                    scheduleNetworkChangeCheck(context)
                }

                override fun onAvailable(network: Network) {
                    scheduleNetworkChangeCheck(context)
                }

                override fun onLost(network: Network) {
                    wasOffline = true
                    scheduleNetworkChangeCheck(context)
                }
            }
            cm.registerDefaultNetworkCallback(callback)
            connectivityManager = cm
            networkCallback = callback
            networkRegistrationAttempts = 0
            pendingNetworkRetry?.let { networkHandler.removeCallbacks(it) }
            pendingNetworkRetry = null
        } catch (_: Exception) {
            val current = MirroringLifecycleStore(context).read()
            if (MirroringLifecyclePolicy.shouldMonitorNetwork(current) &&
                networkRegistrationAttempts++ < 3
            ) {
                val retry = Runnable { registerNetworkCallback(context) }
                pendingNetworkRetry = retry
                networkHandler.postDelayed(retry, 1_000L)
            }
        }
    }

    private fun unregisterNetworkCallback() {
        pendingNetworkRetry?.let { networkHandler.removeCallbacks(it) }
        pendingNetworkRetry = null
        pendingNetworkChange?.let { networkHandler.removeCallbacks(it) }
        pendingNetworkChange = null
        networkRegistrationAttempts = 0
        val callback = networkCallback
        val manager = connectivityManager
        networkCallback = null
        connectivityManager = null
        lastReportedIp = null
        wasOffline = false
        if (callback != null && manager != null) {
            try {
                manager.unregisterNetworkCallback(callback)
            } catch (_: Exception) {
            }
        }
    }

    // NetworkCallback methods don't run on the main thread unless an
    // Executor/Handler is passed to registerDefaultNetworkCallback -- same
    // reason MirrorLineService.enrichFromCallLogThenNotify posts back
    // through a Handler(Looper.getMainLooper()) before touching the
    // MethodChannel.
    private fun scheduleNetworkChangeCheck(context: Context) {
        if (!MirroringLifecyclePolicy.shouldMonitorNetwork(
                MirroringLifecycleStore(context).read(),
            )
        ) {
            unregisterNetworkCallback()
            return
        }
        pendingNetworkChange?.let { networkHandler.removeCallbacks(it) }
        val routerGeneration = NativeEventRouter.generation()
        val check = Runnable {
            try {
                resolverExecutor.execute {
                    val ip = getLocalIp(context)
            // Native-side dedup: only notify Dart when the IP actually
            // changed, so a flapping link doesn't spam the channel. The one
            // exception is recovering from a full link loss (wasOffline):
            // the Dart side must re-discover the peer even when the address
            // came back identical, or it would sit silent until the 90s
            // heartbeat timeout fires.
                    val current = MirroringLifecycleStore(context).read()
                    if (ip != null &&
                        MirroringLifecyclePolicy.shouldMonitorNetwork(current) &&
                        (ip != lastReportedIp || wasOffline)
                    ) {
                        lastReportedIp = ip
                        wasOffline = false
                        NativeEventRouter.routeIfCurrent(
                            routerGeneration,
                            "onNetworkChanged",
                            mapOf("localIp" to ip),
                        )
                    }
                }
            } catch (_: RejectedExecutionException) {
                if (MirroringLifecyclePolicy.shouldMonitorNetwork(
                        MirroringLifecycleStore(context).read(),
                    )
                ) {
                    networkHandler.postDelayed(
                        { scheduleNetworkChangeCheck(context) },
                        NETWORK_CHANGE_DEBOUNCE_MS,
                    )
                }
            }
        }
        pendingNetworkChange = check
        networkHandler.postDelayed(check, NETWORK_CHANGE_DEBOUNCE_MS)
    }

    /** Called by MainActivity.onRequestPermissionsResult once granted. */
    fun onPermissionsGranted() {
        activityRef?.get()?.let { MirroringServiceController.start(it) }
    }

    fun hasAllPermissions(context: Context): Boolean = requiredPermissions.all {
        ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
    }

    private fun ensureAndStart(context: Context): ServiceResult {
        if (hasAllPermissions(context)) {
            val serviceResult = MirroringServiceController.start(context)
            if (serviceResult.outcome == ServiceOutcome.START_REQUESTED) {
                reconcileNetworkMonitoring(context)
            }
            return serviceResult
        }
        // Requesting runtime permissions requires a live Activity. If none
        // is currently resumed (e.g. this is a headless restart with no
        // UI), there's nothing to do until the user opens the app once.
        activityRef?.get()?.let { requestTelephonyPermissions(it) }
        return ServiceResult(ServiceOutcome.PERMISSIONS_REQUIRED)
    }

    private fun requestTelephonyPermissions(activity: MainActivity) {
        val missing = (requiredPermissions.toList() + optionalPermissions.toList()).filter {
            ContextCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            ActivityCompat.requestPermissions(
                activity,
                missing.toTypedArray(),
                TELEPHONY_PERMISSIONS_REQUEST_CODE
            )
        }
    }

    private fun sendSms(context: Context, address: String, body: String, operationId: String) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.SEND_SMS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("SEND_SMS permission not granted")
        }
        if (address.isEmpty()) {
            throw IllegalArgumentException("Recipient address is empty")
        }
        if (operationId.isEmpty()) {
            throw IllegalArgumentException("Operation ID is empty")
        }

        val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }

        val sentAction = "$CHANNEL_NAME.SMS_SENT.$operationId"
        val deliveredAction = "$CHANNEL_NAME.SMS_DELIVERED.$operationId"
        val parts = smsManager.divideMessage(body)
        val multipartParts = parts?.takeIf { it.size > 1 }
        val partCount = multipartParts?.size ?: 1
        registerSmsResultReceiver(context, sentAction, "onSmsSent", operationId, partCount)
        registerSmsResultReceiver(
            context,
            deliveredAction,
            "onSmsDelivered",
            operationId,
            partCount,
        )
        fun pendingIntent(action: String, requestCode: Int): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                requestCode,
                Intent(action).setPackage(context.packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        if (multipartParts != null) {
            smsManager.sendMultipartTextMessage(
                address,
                null,
                multipartParts,
                ArrayList(List(partCount) { index ->
                    pendingIntent(sentAction, operationId.hashCode() + index)
                }),
                ArrayList(List(partCount) { index ->
                    pendingIntent(
                        deliveredAction,
                        (operationId.hashCode() xor 0x40000000) + index,
                    )
                }),
            )
        } else {
            smsManager.sendTextMessage(
                address,
                null,
                body,
                pendingIntent(sentAction, operationId.hashCode()),
                pendingIntent(deliveredAction, operationId.hashCode() xor 0x40000000),
            )
        }
    }

    private fun registerSmsResultReceiver(
        context: Context,
        action: String,
        event: String,
        operationId: String,
        expectedResults: Int,
    ) {
        var receivedResults = 0
        var successful = true
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(receiverContext: Context, intent: Intent) {
                successful = successful && resultCode == android.app.Activity.RESULT_OK
                receivedResults++
                if (receivedResults == expectedResults) {
                    NativeEventRouter.route(
                        event,
                        mapOf("operationId" to operationId, "success" to successful),
                    )
                    receiverContext.unregisterReceiver(this)
                }
            }
        }
        val filter = IntentFilter(action)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    private fun rejectCall(context: Context): Boolean {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.ANSWER_PHONE_CALLS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return try {
            val telecomManager = context.getSystemService(TelecomManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                telecomManager.endCall()
            } else {
                rejectCallViaReflection(context)
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun rejectCallViaReflection(context: Context): Boolean {
        return try {
            val telephonyService = context.getSystemService(Context.TELEPHONY_SERVICE)
            val getITelephony = telephonyService.javaClass.getMethod("getITelephony")
            getITelephony.isAccessible = true
            val telephony = getITelephony.invoke(telephonyService)
            CallRejectionResult.actualBoolean(
                telephony.javaClass.getMethod("endCall").invoke(telephony),
            )
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Returns the IPv4 address of the active LAN network.
     *
     * Prefers the WiFi network (so a simultaneously active mobile data
     * connection does not yield a carrier IP). Falls back to the active
     * network's link properties. Uses ConnectivityManager/LinkProperties,
     * which is the reliable way to get the real address on Android
     * (dart:io's NetworkInterface.list is unreliable here).
     */
    private fun getLocalIp(context: Context): String? {
        return try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

            fun ipOf(props: android.net.LinkProperties?): String? =
                props?.linkAddresses
                    ?.mapNotNull { it.address }
                    ?.filter { it is Inet4Address && !it.isLoopbackAddress }
                    ?.map { it.hostAddress }
                    ?.firstOrNull()

            // 1) Prefer a validated WiFi network.
            cm.allNetworks.forEach { network ->
                val caps = cm.getNetworkCapabilities(network) ?: return@forEach
                if (caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) &&
                    caps.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                ) {
                    val ip = ipOf(cm.getLinkProperties(network))
                    if (ip != null) return ip
                }
            }

            // 2) Fall back to the active network.
            ipOf(cm.getLinkProperties(cm.activeNetwork ?: return null))
        } catch (e: Exception) {
            null
        }
    }

    private fun isNotificationListenerEnabled(context: Context): Boolean {
        val flat = android.provider.Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        val componentName = android.content.ComponentName(context, MirrorLineNotificationListener::class.java)
        val expected = componentName.flattenToString()
        return flat.split(":").any { it == expected }
    }

    private fun openNotificationListenerSettings(context: Context) {
        val intent = Intent(android.provider.Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    private fun runResolver(result: MethodChannel.Result, block: () -> Any?) {
        try {
            resolverExecutor.execute {
                try {
                    val value = block()
                    networkHandler.post { result.success(value) }
                } catch (exception: Exception) {
                    networkHandler.post {
                        result.error("NATIVE_RESOLUTION_FAILED", exception.message, null)
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error("NATIVE_EXECUTOR_BUSY", "Native resolver queue is full", null)
        }
    }
}

object CallRejectionResult {
    fun actualBoolean(value: Any?): Boolean = value as? Boolean ?: false
}
