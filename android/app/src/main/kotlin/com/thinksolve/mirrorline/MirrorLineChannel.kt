package com.thinksolve.mirrorline

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.telecom.TelecomManager
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import java.net.Inet4Address

/**
 * Owns the "com.thinksolve.mirrorline/telephony" MethodChannel and its
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
    const val CHANNEL_NAME = "com.thinksolve.mirrorline/telephony"
    const val TELEPHONY_PERMISSIONS_REQUEST_CODE = 1001

    var channel: MethodChannel? = null
        private set

    private var activityRef: WeakReference<MainActivity>? = null

    private val requiredPermissions = buildList {
        add(Manifest.permission.READ_PHONE_STATE)
        add(Manifest.permission.READ_CALL_LOG)
        add(Manifest.permission.ANSWER_PHONE_CALLS)
        add(Manifest.permission.RECEIVE_SMS)
        add(Manifest.permission.SEND_SMS)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            add(Manifest.permission.FOREGROUND_SERVICE_PHONE_CALL)
        }
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

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening", "startService" -> {
                    ensureAndStart(appContext)
                    result.success(null)
                }
                "stopListening", "stopService" -> {
                    stopMirrorService(appContext)
                    result.success(null)
                }
                "rejectCall" -> result.success(rejectCall(appContext))
                "sendSms" -> {
                    val address = call.argument<String>("address") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    try {
                        sendSms(appContext, address, body)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SMS_SEND_FAILED", e.message, null)
                    }
                }
                "getLocalIp" -> result.success(getLocalIp(appContext))
                "isNotificationListenerEnabled" -> result.success(isNotificationListenerEnabled(appContext))
                "openNotificationListenerSettings" -> {
                    openNotificationListenerSettings(appContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Called by MainActivity.onRequestPermissionsResult once granted. */
    fun onPermissionsGranted() {
        activityRef?.get()?.let { startMirrorService(it) }
    }

    fun hasAllPermissions(context: Context): Boolean = requiredPermissions.all {
        ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
    }

    private fun ensureAndStart(context: Context) {
        if (hasAllPermissions(context)) {
            startMirrorService(context)
            return
        }
        // Requesting runtime permissions requires a live Activity. If none
        // is currently resumed (e.g. this is a headless restart with no
        // UI), there's nothing to do until the user opens the app once.
        activityRef?.get()?.let { requestTelephonyPermissions(it) }
    }

    private fun startMirrorService(context: Context) {
        val intent = Intent(context, MirrorLineService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    private fun stopMirrorService(context: Context) {
        context.stopService(Intent(context, MirrorLineService::class.java))
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

    private fun sendSms(context: Context, address: String, body: String) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.SEND_SMS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("SEND_SMS permission not granted")
        }
        if (address.isEmpty()) {
            throw IllegalArgumentException("Recipient address is empty")
        }

        val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }

        val parts = smsManager.divideMessage(body)
        if (parts != null && parts.size > 1) {
            smsManager.sendMultipartTextMessage(address, null, parts, null, null)
        } else {
            smsManager.sendTextMessage(address, null, body, null, null)
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
            true
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
            telephony.javaClass.getMethod("endCall").invoke(telephony)
            true
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
}
