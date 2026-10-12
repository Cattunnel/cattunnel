package com.adguard.trusttunnel

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Connects to the last server for the Quick Settings tile when the vendor
 * service has no saved configuration (it forgets it on every stop).
 *
 * - The app is running (its engine is alive, even in the background): Dart
 *   is told "launched from the tile" over the existing channel and connects
 *   as on a tile launch, no window shown.
 * - It isn't: a windowless engine runs the Dart entry point `tileConnect`
 *   (lib/feature/vpn/tile_connect.dart), which builds the configuration the
 *   same way a tap in the app does, starts the VPN and reports `done`; the
 *   engine is destroyed then (or after [TIMEOUT_MS]).
 *
 * Everything here runs on the main thread.
 */
object TileConnector {
    private const val CHANNEL = "cattunnel/tile_connect"
    private const val TIMEOUT_MS = 45_000L

    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var onDone: ((Boolean) -> Unit)? = null

    val busy: Boolean get() = engine != null

    /** [done] gets whether the VPN was started; not called again while busy. */
    fun connect(context: Context, done: (Boolean) -> Unit) {
        CatTunnelActivity.liveTileLaunchChannel?.let { channel ->
            channel.invokeMethod("launchedFromTile", null)
            done(true)

            return
        }
        if (busy) return

        val appContext = context.applicationContext
        onDone = done
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(appContext)
        loader.ensureInitializationCompleteAsync(appContext, null, main) {
            val newEngine = FlutterEngine(appContext)
            engine = newEngine
            val messenger = newEngine.dartExecutor.binaryMessenger
            // The configuration needs these (system CA bundle, app split).
            SecurityChannel(appContext, messenger)
            AppsChannel(appContext, messenger)
            MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
                if (call.method == "done") {
                    result.success(null)
                    finish(call.arguments as? Boolean ?: false)
                } else {
                    result.notImplemented()
                }
            }
            newEngine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "tileConnect"),
            )
            main.postDelayed({ finish(false) }, TIMEOUT_MS)
        }
    }

    private fun finish(connected: Boolean) {
        val current = engine ?: return
        main.removeCallbacksAndMessages(null)
        engine = null
        current.destroy()
        onDone?.invoke(connected)
        onDone = null
    }
}
