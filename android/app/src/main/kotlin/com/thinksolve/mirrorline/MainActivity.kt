package com.thinksolve.mirrorline

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val telephonyChannelName = "com.thinksolve.mirrorline/telephony"
    private val requiredPermissions = arrayOf(
        Manifest.permission.READ_PHONE_STATE,
        Manifest.permission.READ_CALL_LOG,
        Manifest.permission.ANSWER_PHONE_CALLS,
        Manifest.permission.RECEIVE_SMS,
        Manifest.permission.SEND_SMS,
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            telephonyChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> {
                    requestTelephonyPermissions()
                    result.success(null)
                }
                "stopListening" -> result.success(null)
                "rejectCall" -> {
                    // Requires telecom permission; implement via TelecomManager.endCall() if permitted.
                    result.success(null)
                }
                "sendSms" -> {
                    val address = call.argument<String>("address") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    sendSms(address, body)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestTelephonyPermissions() {
        val missing = requiredPermissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, missing.toTypedArray(), TELEPHONY_PERMISSIONS_CODE)
        }
    }

    private fun sendSms(address: String, body: String) {
        // Use android.telephony.SmsManager in a real implementation.
        // Placeholder for compile safety.
    }

    companion object {
        private const val TELEPHONY_PERMISSIONS_CODE = 1001
    }
}
