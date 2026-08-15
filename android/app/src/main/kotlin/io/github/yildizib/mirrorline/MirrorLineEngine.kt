package io.github.yildizib.mirrorline

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * A single FlutterEngine shared by MainActivity and MirrorLineService for
 * the whole lifetime of the app process.
 *
 * Without this, each Activity instance got its own default engine that was
 * destroyed in onDestroy() (e.g. when the app is swiped from recents or the
 * Activity is reclaimed while the screen is off). That killed the entire
 * Dart isolate -- including the TCP socket, beacon broadcaster/listener and
 * heartbeat living in ConnectionNotifier -- even though MirrorLineService's
 * foreground notification kept showing "MirrorLine çalışıyor". Keeping one
 * engine alive for the process lets the mirroring connection survive
 * Activity destruction as long as the foreground service itself is alive.
 */
object MirrorLineEngine {
    private const val ENGINE_ID = "mirrorline_shared_engine"

    @Synchronized
    fun getOrCreate(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }

        val engine = FlutterEngine(context.applicationContext)
        // Wire the telephony channel to this engine directly (not to any
        // one Activity) so it works whether the engine was created by
        // MainActivity or, as with a headless service restart, by
        // MirrorLineService alone.
        MirrorLineChannel.attach(context, engine)
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        return engine
    }
}
