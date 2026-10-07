package com.adguard.trusttunnel

import android.app.ActivityManager
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
 * (including ours below), so a reconnect only works if the VPN was last left
 * running (e.g. killed by the system) rather than manually disconnected - in
 * that case we fall back to opening the app, marked as a tile launch so it
 * connects to the last server right away (see CatTunnelActivity).
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

        if (!VpnService.isPrepared(applicationContext)) {
            openApp()

            return
        }

        val config = VpnConfigStorage(applicationContext).load()
        if (config.isNullOrEmpty()) {
            openApp()

            return
        }

        VpnService.start(applicationContext, config)
        setTileState(Tile.STATE_ACTIVE)
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

    /**
     * Whether *our* VPN service is up. Checking for any VPN transport on the
     * active network would also count another app's VPN - the tile would show
     * "on" and a tap would try to stop ours. Since Android 8,
     * getRunningServices only returns the caller's own services, which is
     * exactly the question here.
     */
    @Suppress("DEPRECATION")
    private fun isVpnActive(): Boolean {
        val activityManager = applicationContext.getSystemService(ActivityManager::class.java) ?: return false

        return activityManager.getRunningServices(Int.MAX_VALUE).any {
            it.service.className == VpnService::class.java.name && it.foreground
        }
    }

    @Suppress("DEPRECATION")
    private fun openApp() {
        val intent = Intent(applicationContext, CatTunnelActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra(CatTunnelActivity.EXTRA_FROM_TILE, CatTunnelActivity.tileLaunchToken)
        }

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
