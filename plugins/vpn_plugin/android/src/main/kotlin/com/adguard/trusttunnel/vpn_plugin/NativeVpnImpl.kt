// plugins/vpn_plugin/android/src/main/kotlin/com/adguard/trusttunnel/vpn_plugin/NativeVpnImpl.kt
package com.adguard.trusttunnel.vpn_plugin

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.ArrayDeque
import java.util.Queue
import com.adguard.trusttunnel.AppNotifier
import com.adguard.trusttunnel.Logger
import com.adguard.trusttunnel.VpnService
import io.flutter.plugin.common.EventChannel
import java.io.File

class NativeVpnImpl(
    private val appContext: Context
) : EventChannel.StreamHandler, AppNotifier {

    private var events: EventChannel.EventSink? = null
    private var currentState = VpnManagerState.DISCONNECTED
    private val main = Handler(Looper.getMainLooper())
    private val log = Logger("VPN_PLUGIN")

    val queryLogHandler: QueryLogStreamHandler = QueryLogStreamHandler()

    /** Why the server couldn't be reached, see [onConnectionInfo]. */
    val failureHandler: FailureStreamHandler = FailureStreamHandler()

    /**
     * The query log is a per-connection record (domain, destination, time) -
     * effectively browsing history. Keep it session-scoped: outside backups
     * (noBackupFilesDir), wiped on every app start and every disconnect (see
     * [onStateChanged]). The
     * vendor ring buffer reopens the file by path on each append, so deleting
     * it in between is safe.
     */
    private val queryLogFile = File(appContext.noBackupFilesDir, QUERY_LOG_FILE_NAME)

    init {
        VpnService.initialize(appContext)
        // 1.2.0 and older kept it in filesDir, where it was backed up.
        File(appContext.filesDir, QUERY_LOG_FILE_NAME).delete()
        queryLogFile.delete()
        VpnService.setAppNotifier(queryLogFile, this)
    }

    fun startPrepared(ctx: Context, config: String) {
        log.info("startPrepared()")
        VpnService.start(ctx, config)
    }

    fun stop() {
        log.info("stop()")
        VpnService.stop(appContext)
    }

    fun exportLogs(): List<String> {
        log.info("exportLogs()")
        return VpnService.exportLogs(appContext)
    }

    fun clearLogs() {
        log.info("clearLogs()")
        VpnService.clearLogs()
    }

    fun getCurrentState(): VpnManagerState = currentState

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        log.info("onListen() -> subscribe state notifier")
        this.events = events
        postEvent(currentState.ordinal)
    }

    override fun onCancel(arguments: Any?) {
        log.info("onCancel() -> unsubscribe")
        try {
            events = null
        } catch (t: Throwable) {
            log.warn("clearStateNotifier failed", t)
        }
    }

    override fun onStateChanged(state: Int) {
        log.info("onStateChanged($state)")
        currentState = VpnManagerState.entries[state]
        // Any way the tunnel went down (app, QS tile, system settings).
        if (currentState == VpnManagerState.DISCONNECTED) {
            queryLogFile.delete()
        }
        postEvent(state)
    }

    override fun onConnectionInfo(info: String) {
        log.debug("onConnectionInfo")
        // Our engine build (patch 0001-anti-dpi-desync, lib.cpp onPingFailed)
        // sends {"cattunnel_failure":"..."} here after every failed attempt: why the
        // server couldn't be reached. Not a query log record.
        FAILURE_RECORD.matchEntire(info)?.let {
            failureHandler.onFailure(it.groupValues[1])
            return
        }
        queryLogHandler.onQueryLog(info)
    }

    private fun postEvent(value: Any) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            events?.success(value)
        } else {
            main.post { events?.success(value) }
        }
    }
}

private const val QUERY_LOG_FILE_NAME = "query_log.dat"

private val FAILURE_RECORD = Regex("""\{"cattunnel_failure":"([a-z_]+)"\}""")

/** Live only: a failure nobody listened to is stale by the next listen. */
class FailureStreamHandler : EventChannel.StreamHandler {
    private var events: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.events = events
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    fun onFailure(failure: String) {
        main.post { events?.success(failure) }
    }
}

class QueryLogStreamHandler : EventChannel.StreamHandler {

    private var events: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())
    private val queue: Queue<String> = ArrayDeque()
    private val log = Logger("VPN_PLUGIN")

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        log.info("QueryLog#onListen() -> subscribe state notifier")
        this.events = events
        for (log in queue) {
            postEvent(log)
        }
        queue.clear()
    }

    override fun onCancel(arguments: Any?) {
        log.info("QueryLog#onCancel() -> unsubscribe")
        try {
            events = null
        } catch (t: Throwable) {
            log.warn("clearNotifier failed for QueryLog", t)
        }
    }

    private fun postEvent(value: Any) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            events?.success(value)
        } else {
            main.post { events?.success(value) }
        }
    }

    fun onQueryLog(log: String) {
        main.post {
            if (events == null) {
                queue.offer(log)
            } else {
                postEvent(log)
            }
        }
    }
}
