package com.adguard.trusttunnel

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import android.service.quicksettings.TileService

/**
 * The Quick Settings tile's connect, as an invisible activity.
 *
 * Some firmwares (Samsung, Android 16) report the VPN as not prepared after
 * every stop, although the person consented long ago - and a tile service
 * can't ask for it, nor can the app's backgrounded window. A foreground
 * activity can: for an app that already has the consent the system grants it
 * at once, with no dialog (a first-time consent shows the system dialog).
 * Then [TileConnector] connects; on failure the app opens, from here, while
 * we're still allowed to start it. Transparent, no animation, not in Recents,
 * gone after [MAX_WAIT_MS] at the latest.
 */
class TileConnectActivity : Activity() {
    private var finished = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        overridePendingTransition(0, 0)
        window.decorView.postDelayed({ close() }, MAX_WAIT_MS)
        if (savedInstanceState != null) return

        val prepare = android.net.VpnService.prepare(this)
        TileLog.i(this, "tile ${if (stopping) "stop" else "connect"}: prepared=${prepare == null}")
        if (prepare == null) {
            proceed()
        } else {
            runCatching { startActivityForResult(prepare, REQ_PREPARE) }
                .onFailure {
                    TileLog.i(this, "tile connect: consent not available (${it.javaClass.simpleName})")
                    openApp()
                }
        }
    }

    @Deprecated("Activity API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PREPARE) return
        TileLog.i(this, "tile connect: consent result=$resultCode")
        if (resultCode == RESULT_OK) proceed() else close()
    }

    private val stopping: Boolean get() = intent?.action == ACTION_STOP

    private fun proceed() {
        if (!stopping) {
            connect()

            return
        }
        VpnService.stop(applicationContext)
        TileLog.i(this, "tile stop: requested")
        TileService.requestListeningState(
            applicationContext,
            ComponentName(applicationContext, CatTunnelQsTileService::class.java),
        )
        close()
    }

    private fun connect() {
        TileConnector.connect(applicationContext) { connected ->
            TileService.requestListeningState(
                applicationContext,
                ComponentName(applicationContext, CatTunnelQsTileService::class.java),
            )
            if (connected) close() else openApp()
        }
    }

    private fun openApp() {
        if (!finished) {
            startActivity(
                Intent(this, CatTunnelActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    putExtra(CatTunnelActivity.EXTRA_FROM_TILE, CatTunnelActivity.tileLaunchToken)
                },
            )
        }
        close()
    }

    private fun close() {
        if (finished) return
        finished = true
        finish()
        overridePendingTransition(0, 0)
    }

    companion object {
        const val ACTION_STOP = "com.adguard.trusttunnel.TILE_STOP"

        private const val REQ_PREPARE = 0x7117
        private const val MAX_WAIT_MS = 20_000L
    }
}
