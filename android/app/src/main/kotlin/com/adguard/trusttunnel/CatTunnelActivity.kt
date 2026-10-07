package com.adguard.trusttunnel

import android.content.Intent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Hands "opened from the Quick Settings tile" over to Dart, which then
 * connects to the last server even with auto-connect on launch disabled
 * (see CatTunnelQsTileService.openApp and AutoConnectOnLaunchSettingsScope).
 *
 * Cold start: Dart pulls the flag once via `consumeLaunchedFromTile`.
 * Already running (singleTask -> onNewIntent): pushed via `launchedFromTile`.
 *
 * Also toggles FLAG_SECURE for screens that show keys (see SecureScreen on
 * the Dart side) and hosts [SecurityChannel].
 *
 * A FlutterFragmentActivity because local_auth (app lock) needs a
 * FragmentActivity for BiometricPrompt.
 *
 * Launched through the `.MainActivity` / `.LauncherCalculator` aliases (see
 * the manifest): the default alias keeps the pre-1.3.5 component name, so
 * home-screen shortcuts made by older versions keep working after updating.
 */
class CatTunnelActivity : FlutterFragmentActivity() {

    private var launchedFromTile = false
    private var tileLaunchChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        launchedFromTile = consumeTileExtra(intent)
        tileLaunchChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TILE_LAUNCH_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumeLaunchedFromTile" -> {
                        result.success(launchedFromTile)
                        launchedFromTile = false
                    }
                    else -> result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_SCREEN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    if (call.arguments == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        SecurityChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        UpdateChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        AppsChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)

        if (consumeTileExtra(intent)) {
            tileLaunchChannel?.invokeMethod("launchedFromTile", null)
        }
    }

    /**
     * Reads and clears the tile marker, ignoring re-deliveries from Recents.
     *
     * This activity is exported (launcher + tt:// links), so any app could
     * send the extra - it only counts when it carries [tileLaunchToken],
     * which never leaves this process (the tile service runs in it too).
     */
    private fun consumeTileExtra(intent: Intent?): Boolean {
        val token = intent?.getStringExtra(EXTRA_FROM_TILE) ?: return false

        intent.removeExtra(EXTRA_FROM_TILE)

        return token == tileLaunchToken &&
            (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == 0
    }

    companion object {
        const val EXTRA_FROM_TILE = "cattunnel.from_tile"
        private const val TILE_LAUNCH_CHANNEL = "cattunnel/tile_launch"
        private const val SECURE_SCREEN_CHANNEL = "cattunnel/secure_screen"

        /** Per-process secret for [EXTRA_FROM_TILE]. */
        val tileLaunchToken: String = UUID.randomUUID().toString()
    }
}
