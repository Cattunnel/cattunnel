package com.adguard.trusttunnel

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

/** `cattunnel/traffic`: `read` - [TrafficRecorder.snapshot] (lib/feature/traffic). */
class TrafficChannel(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())

    init {
        MethodChannel(messenger, "cattunnel/traffic").setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "read" -> thread(name = "cattunnel-traffic-read") {
                val text = runCatching { TrafficRecorder.snapshot() }
                main.post {
                    text.fold({ result.success(it) }, { result.error("traffic_error", it.message, null) })
                }
            }
            else -> result.notImplemented()
        }
    }
}
