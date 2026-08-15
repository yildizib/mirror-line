package io.github.yildizib.mirrorline

import android.content.Context
import android.content.Intent
import android.os.Build

enum class ServiceOutcome { START_REQUESTED, STOPPED, INELIGIBLE, PERMISSIONS_REQUIRED, FAILED }

data class ServiceResult(val outcome: ServiceOutcome, val error: String? = null) {
    fun toMap(): Map<String, Any?> = mapOf(
        "outcome" to outcome.name.lowercase(),
        "error" to error,
    )
}

object MirroringServiceController {
    fun lifecycle(context: Context): Pair<MirroringLifecycleState, Boolean> {
        val state = MirroringLifecycleStore(context).read()
        return state to MirrorLineChannel.hasAllPermissions(context)
    }

    fun isEligible(context: Context): Boolean {
        val (state, permissions) = lifecycle(context)
        return MirroringLifecyclePolicy.isEligible(state, permissions)
    }

    fun start(context: Context): ServiceResult {
        val appContext = context.applicationContext
        val (state, permissions) = lifecycle(appContext)
        if (!permissions) return ServiceResult(ServiceOutcome.PERMISSIONS_REQUIRED)
        if (!MirroringLifecyclePolicy.isEligible(state, true)) {
            Watchdog.cancel(appContext)
            return ServiceResult(ServiceOutcome.INELIGIBLE)
        }
        return try {
            val intent = Intent(appContext, MirrorLineService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                appContext.startForegroundService(intent)
            } else {
                appContext.startService(intent)
            }
            ServiceResult(ServiceOutcome.START_REQUESTED)
        } catch (exception: Exception) {
            ServiceResult(ServiceOutcome.FAILED, exception.message ?: exception.javaClass.simpleName)
        }
    }

    fun stop(
        context: Context,
        sync: MirroringLifecycleState? = null,
        clearNativeEvents: Boolean = true,
    ): ServiceResult {
        val appContext = context.applicationContext
        if (sync != null) {
            MirroringLifecycleStore(appContext).sync(sync.enabled, sync.role, sync.paired)
        }
        Watchdog.cancel(appContext)
        MirrorLineNotificationListener.cancelPendingRebind()
        MirrorLineNotificationListener.clearPendingNotifications()
        if (clearNativeEvents) NativeEventRouter.notReady()
        appContext.stopService(Intent(appContext, MirrorLineService::class.java))
        return ServiceResult(ServiceOutcome.STOPPED)
    }
}
