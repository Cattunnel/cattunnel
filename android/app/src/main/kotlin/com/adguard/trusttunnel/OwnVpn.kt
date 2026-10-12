package com.adguard.trusttunnel

import android.app.ActivityManager
import android.content.Context

object OwnVpn {
    /**
     * Whether *our* VPN service is up. Checking for any VPN transport on the
     * active network would also count another app's VPN. Since Android 8,
     * getRunningServices only returns the caller's own services, which is
     * exactly the question here.
     */
    @Suppress("DEPRECATION")
    fun isActive(context: Context): Boolean {
        val activityManager = context.getSystemService(ActivityManager::class.java) ?: return false

        return activityManager.getRunningServices(Int.MAX_VALUE).any {
            it.service.className == VpnService::class.java.name && it.foreground
        }
    }
}
