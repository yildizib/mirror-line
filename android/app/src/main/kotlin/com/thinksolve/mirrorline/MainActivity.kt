package com.thinksolve.mirrorline

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.telecom.TelecomManager
import android.telephony.SmsManager
import java.net.Inet4Address
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        )
        channel = methodChannel

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
 "startListening" -> {
 ensureAndStart()
 result.success(null)
 }
                "stopListening" -> {
                    stopMirrorService()
                    result.success(null)
                }
                "rejectCall" -> {
                    result.success(rejectCall())
                }
                "sendSms" -> {
                    val address = call.argument<String>("address") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    try {
                        sendSms(address, body)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SMS_SEND_FAILED", e.message, null)
                    }
                }
 "startService" -> {
 ensureAndStart()
 result.success(null)
 }
                "stopService" -> {
                    stopMirrorService()
                    result.success(null)
                }
                "getLocalIp" -> {
                    result.success(getLocalIp())
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
 requestCode: Int,
 permissions: Array<out String>,
 grantResults: IntArray
 ) {
 super.onRequestPermissionsResult(requestCode, permissions, grantResults)
 if (requestCode == TELEPHONY_PERMISSIONS_CODE && hasAllPermissions()) {
 startMirrorService()
 }
 }

 override fun onDestroy() {
        if (isFinishing) {
            channel = null
        }
        super.onDestroy()
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
    private fun getLocalIp(): String? {
        return try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

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

    private fun sendSms(address: String, body: String) {        if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("SEND_SMS permission not granted")
        }
        if (address.isEmpty()) {
            throw IllegalArgumentException("Recipient address is empty")
        }

        val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(SmsManager::class.java)
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

    private fun rejectCall(): Boolean {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ANSWER_PHONE_CALLS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return try {
            val telecomManager = getSystemService(TelecomManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                telecomManager.endCall()
            } else {
                rejectCallViaReflection()
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun rejectCallViaReflection(): Boolean {
        return try {
            val telephonyService = getSystemService(Context.TELEPHONY_SERVICE)
            val getITelephony = telephonyService.javaClass.getMethod("getITelephony")
            getITelephony.isAccessible = true
            val telephony = getITelephony.invoke(telephonyService)
            telephony.javaClass.getMethod("endCall").invoke(telephony)
            true
        } catch (e: Exception) {
            false
        }
    }

 private fun ensureAndStart() {
 if (hasAllPermissions()) {
 startMirrorService()
 } else {
 requestTelephonyPermissions()
 }
 }

 private fun startMirrorService() {
 val intent = Intent(this, MirrorLineService::class.java)
 if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopMirrorService() {
        stopService(Intent(this, MirrorLineService::class.java))
    }

 private fun hasAllPermissions(): Boolean = requiredPermissions.all {
 ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
 }

 private fun requestTelephonyPermissions() {
 val missing = requiredPermissions.filter {
 ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
 }
        if (missing.isNotEmpty()) {
            ActivityCompat.requestPermissions(
                this,
                missing.toTypedArray(),
                TELEPHONY_PERMISSIONS_CODE
            )
        }
    }

    companion object {
        private const val CHANNEL_NAME = "com.thinksolve.mirrorline/telephony"
        private const val TELEPHONY_PERMISSIONS_CODE = 1001

        var channel: MethodChannel? = null
            private set
    }
}
