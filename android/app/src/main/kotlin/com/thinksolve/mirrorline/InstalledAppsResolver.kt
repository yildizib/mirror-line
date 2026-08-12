package com.thinksolve.mirrorline

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import java.io.ByteArrayOutputStream

/**
 * Lists launchable apps and resolves their icons, for the Watched Apps
 * screen (per-app notification-mirroring opt-in). Uses the MAIN/LAUNCHER
 * intent-filter query declared in AndroidManifest.xml's <queries> block
 * rather than QUERY_ALL_PACKAGES, which would require a Play Console
 * declaration -- also a reasonable scope limit, since a non-launchable app
 * (a background service/library with no icon of its own) isn't something
 * a user would meaningfully "watch" or "unwatch" by name.
 */
object InstalledAppsResolver {
    private const val MAX_ICON_SIZE = 96

    fun list(context: Context): List<Map<String, String>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(intent, 0)
            .map { info ->
                mapOf(
                    "packageName" to info.activityInfo.packageName,
                    "appName" to info.loadLabel(pm).toString()
                )
            }
            .distinctBy { it["packageName"] }
            .sortedBy { it["appName"]?.lowercase() ?: "" }
    }

    fun iconBytes(context: Context, packageName: String): ByteArray? {
        return try {
            val drawable = context.packageManager.getApplicationIcon(packageName)
            val bitmap = drawableToBitmap(drawable)
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        } catch (_: Exception) {
            null
        }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        val width = drawable.intrinsicWidth.coerceIn(1, MAX_ICON_SIZE)
        val height = drawable.intrinsicHeight.coerceIn(1, MAX_ICON_SIZE)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }
}
