package com.adguard.trusttunnel

import android.app.Application

/** Starts [TrafficRecorder] with the process - the VPN service runs in it too. */
class CatTunnelApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        TrafficRecorder.start(this)
    }
}
