package com.thinksolve.mirrorline

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings

/**
 * Many Android OEMs (Xiaomi/HyperOS, Huawei, OPPO, Vivo, Samsung...) layer
 * their own "autostart" / background-activity restrictions on top of stock
 * Android's battery optimization system. A foreground service + wake lock +
 * ignoring battery optimizations (see MirrorLineService, PermissionService)
 * isn't enough on these ROMs -- the OEM's own manager can still freeze the
 * app or kill its Wi-Fi lock while the screen is off, unless the user
 * separately allows it there.
 *
 * These component names are undocumented, OEM-internal, and can change
 * between ROM versions -- this is the same best-effort approach widely used
 * by other "keep my app alive" apps (see dontkillmyapp.com). Every launch
 * attempt is wrapped so a missing/renamed component just falls through to
 * the next option instead of crashing.
 */
object OemAutoStart {
    private data class Target(val pkg: String, val cls: String)

    private val targetsByManufacturer: Map<String, List<Target>> = mapOf(
        "xiaomi" to listOf(
            Target("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
        ),
        "huawei" to listOf(
            Target(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            ),
            Target("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"),
        ),
        "honor" to listOf(
            Target(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            ),
        ),
        "oppo" to listOf(
            Target(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity"
            ),
            Target("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity"),
            Target(
                "com.oppo.safe",
                "com.oppo.safe.permission.startup.StartupAppListActivity"
            ),
        ),
        "vivo" to listOf(
            Target(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
            ),
        ),
        "samsung" to listOf(
            Target("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity"),
        ),
        "oneplus" to listOf(
            Target(
                "com.oneplus.security",
                "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"
            ),
        ),
    )

    private fun candidatesForThisDevice(): List<Target> {
        val manufacturer = Build.MANUFACTURER.lowercase()
        return targetsByManufacturer.entries
            .firstOrNull { (key, _) -> manufacturer.contains(key) }
            ?.value
            ?: emptyList()
    }

    /** Whether we know of an OEM-specific screen for this device's manufacturer. */
    fun hasKnownScreen(): Boolean = candidatesForThisDevice().isNotEmpty()

    /**
     * Opens the OEM's autostart/background-activity manager if we have a
     * known component for this device's manufacturer, otherwise falls back
     * to this app's own "App info" screen (still useful: it's where most
     * OEMs also surface their custom battery controls).
     */
    fun open(context: Context) {
        for (target in candidatesForThisDevice()) {
            if (tryLaunch(context, target)) return
        }
        openAppDetails(context)
    }

    private fun tryLaunch(context: Context, target: Target): Boolean {
        return try {
            val intent = Intent().apply {
                component = ComponentName(target.pkg, target.cls)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openAppDetails(context: Context) {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", context.packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (_: Exception) {
        }
    }
}
