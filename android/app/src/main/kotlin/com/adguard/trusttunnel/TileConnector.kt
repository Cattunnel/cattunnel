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
 *   is told "launched from the tile" over the existing channel and answers
 *   whether it took it; it then connects as on a tile launch, no window.
 * - It isn't (or Dart didn't take it): a windowless engine runs the Dart
 *   entry point `tileConnect` (lib/feature/vpn/tile_connect.dart), which
 *   builds the configuration the same way a tap in the app does, starts the
 *   VPN and reports `done`; the engine is destroyed then (or after
 *   [TIMEOUT_MS]). The VPN service and its native engine don't need it -
 *   they keep connecting/retrying alone.
 *
 * Everything here runs on the main thread.
 */
object TileConnector {
    private const val CHANNEL = "cattunnel/tile_connect"
    private const val TIMEOUT_MS = 45_000L

    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var onDone: ((Boolean) -> Unit)? = null
    private lateinit var appContext: Context

    /** From the tap until `done` - also while Flutter is still loading. */
    var busy = false
        private set

    /** [done] gets whether the VPN was started; not called again while busy. */
    fun connect(context: Context, done: (Boolean) -> Unit) {
        if (busy) return
        appContext = context.applicationContext
        busy = true
        onDone = done
        main.postDelayed({ finish(false, "timeout") }, TIMEOUT_MS)

        val live = CatTunnelActivity.liveTileLaunchChannel
        if (live == null) {
            startEngine()

            return
        }
        TileLog.i(appContext, "tile connect: asking the running app")
        live.invokeMethod(
            "launchedFromTile",
            null,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (result == true) finish(true, "running app took it") else startEngine()
                }

                override fun error(code: String, message: String?, details: Any?) = startEngine()

                override fun notImplemented() = startEngine()
            },
        )
    }

    private fun startEngine() {
        if (!busy || engine != null) return
        TileLog.i(appContext, "tile connect: windowless engine")
        runCatching {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(appContext)
            loader.ensureInitializationCompleteAsync(appContext, null, main) {
                runCatching {
                    if (!busy) return@runCatching
                    val newEngine = FlutterEngine(appContext)
                    engine = newEngine
                    val messenger = newEngine.dartExecutor.binaryMessenger
                    // The configuration needs these (system CA bundle, app split).
                    SecurityChannel(appContext, messenger)
                    AppsChannel(appContext, messenger)
                    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
                        if (call.method == "done") {
                            result.success(null)
                            val args = call.arguments as? Map<*, *>
                            val why = (args?.get("why") as? String).orEmpty()
                            finish(args?.get("connected") == true, if (why.isEmpty()) "engine reported" else "engine: $why")
                        } else {
                            result.notImplemented()
                        }
                    }
                    newEngine.dartExecutor.executeDartEntrypoint(
                        DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "tileConnect"),
                    )
                }.onFailure { finish(false, "engine start failed: ${it.javaClass.simpleName}") }
            }
        }.onFailure { finish(false, "loader failed: ${it.javaClass.simpleName}") }
    }

    private fun finish(connected: Boolean, why: String) {
        if (!busy) return
        TileLog.i(appContext, "tile connect: done connected=$connected ($why)")
        busy = false
        main.removeCallbacksAndMessages(null)
        engine?.destroy()
        engine = null
        onDone?.invoke(connected)
        onDone = null
    }
}
