package com.adguard.trusttunnel

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * `cattunnel/traffic` (lib/feature/traffic): `read` - [TrafficRecorder.snapshot],
 * `clear` - [TrafficRecorder.clear].
 */
class TrafficChannel(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())

    init {
        MethodChannel(messenger, "cattunnel/traffic").setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val work: () -> Any? = when (call.method) {
            "read" -> TrafficRecorder::snapshot
            "clear" -> {
                { TrafficRecorder.clear() }
            }
            else -> {
                result.notImplemented()

                return
            }
        }
        executor.execute {
            val outcome = runCatching(work)
            main.post {
                outcome.fold({ result.success(it) }, { result.error("traffic_error", it.javaClass.simpleName, null) })
            }
        }
    }

    private companion object {
        val executor = Executors.newSingleThreadExecutor()
    }
}
