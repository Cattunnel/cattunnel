package com.adguard.trusttunnel

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Quick Settings tile that lets the user connect/disconnect the VPN without
 * opening the app.
 *
 * "Connect" reuses the last configuration the vendor VPN service persisted in
 * its own [VpnConfigStorage] (the same storage Always-On VPN relies on). That
 * storage is cleared by the vendor service on every explicit `stop()` call
 * (including ours below), and some firmwares also drop the "prepared" state
 * on every stop. So otherwise the tap goes to the invisible
 * [TileConnectActivity]: it re-prepares the VPN (no dialog once consented)
 * and has [TileConnector] build the configuration in Dart (the running app,
 * or a windowless engine) - no window opens. The app is opened only for a
 * first-time consent the person declines, or when that connect failed.
 */
class CatTunnelQsTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()

        if (isVpnActive()) {
            VpnService.stop(applicationContext)
            setTileState(Tile.STATE_INACTIVE)

            return
        }

        val config = VpnConfigStorage(applicationContext).load()
        val prepared = VpnService.isPrepared(applicationContext)
        TileLog.i(this, "tile click: prepared=$prepared savedConfig=${!config.isNullOrEmpty()} busy=${TileConnector.busy}")
        if (prepared && !config.isNullOrEmpty()) {
            VpnService.start(applicationContext, config)
            setTileState(Tile.STATE_ACTIVE)

            return
        }

        if (TileConnector.busy) return
        setTileState(Tile.STATE_ACTIVE)
        startActivityAndCollapseCompat(Intent(applicationContext, TileConnectActivity::class.java))
    }

    private fun updateTileState() = setTileState(if (isVpnActive()) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE)

    private fun setTileState(state: Int) {
        qsTile?.state = state
        qsTile?.label = if (isDisguised()) getString(R.string.disguise_label) else "CatTunnel"
        qsTile?.updateTile()
    }

    /** The launcher disguise is on (see SecurityChannel.setDisguised). */
    private fun isDisguised(): Boolean = packageManager.getComponentEnabledSetting(
        ComponentName(packageName, "com.adguard.trusttunnel.${SecurityChannel.ALIAS_DISGUISED}"),
    ) == PackageManager.COMPONENT_ENABLED_STATE_ENABLED

    private fun isVpnActive(): Boolean = OwnVpn.isActive(applicationContext)

    @Suppress("DEPRECATION")
    private fun startActivityAndCollapseCompat(target: Intent) {
        val intent = target.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }

        if (android.os.Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(
                PendingIntent.getActivity(
                    applicationContext,
                    0,
                    intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
        } else {
            startActivityAndCollapse(intent)
        }
    }
}
