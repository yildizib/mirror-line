package io.github.yildizib.mirrorlink

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    // Use the single process-wide engine (see MirrorLineEngine) instead of
    // the default per-Activity engine, and don't let onDestroy() tear it
    // down -- the mirroring connection running inside it must survive the
    // Activity being destroyed (backgrounded, swiped away, reclaimed while
    // the screen is off) as long as the foreground service is alive.
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        return MirrorLineEngine.getOrCreate(context)
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    // The telephony MethodChannel itself is wired up once, directly to the
    // shared engine, by MirrorLineEngine.getOrCreate() (see
    // MirrorLineChannel). All this Activity needs to do is make itself
    // available for the one operation that genuinely requires a live
    // Activity: requesting runtime permissions.
    override fun onResume() {
        super.onResume()
        MirrorLineChannel.setActivity(this)
    }

    override fun onPause() {
        MirrorLineChannel.setActivity(null)
        super.onPause()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == MirrorLineChannel.TELEPHONY_PERMISSIONS_REQUEST_CODE &&
            MirrorLineChannel.hasAllPermissions(this)
        ) {
            MirrorLineChannel.onPermissionsGranted()
        }
    }
}
