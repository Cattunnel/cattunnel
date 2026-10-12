package com.adguard.trusttunnel

import android.content.Context
import android.net.TrafficStats
import android.os.Handler
import android.os.HandlerThread
import android.os.Process
import java.io.File

/**
 * The app's own traffic statistics (Settings -> Traffic statistics), kept
 * on the phone only.
 *
 * Every [SAMPLE_MS] while our VPN service is up, the bytes this app's UID
 * sent and received since the last sample (TrafficStats - the engine's
 * sockets to the server are ours, so this is the tunnel's traffic on the
 * wire, encryption included) are added to the current hour and the current
 * server (the id the app keeps as the last picked one). The app's own
 * direct requests while the VPN is off are not counted.
 *
 * File: `filesDir/traffic_hourly.tsv`, lines `hourEpochSec<TAB>serverId<TAB>rx<TAB>tx`.
 * Samples are appended; once an hour the file is folded to one line per
 * hour and server and trimmed to [KEEP_DAYS]. Dart reads it through
 * [TrafficChannel] (and skips a torn last line).
 *
 * All work happens on its own thread.
 */
object TrafficRecorder {
    private const val FILE_NAME = "traffic_hourly.tsv"
    private const val SAMPLE_MS = 30_000L
    private const val KEEP_DAYS = 400L
    private const val SERVER_KEY = "flutter.auto_connect_on_launch_last_server_id"

    private val thread = HandlerThread("cattunnel-traffic").apply { start() }
    private val handler = Handler(thread.looper)

    private lateinit var app: Context
    private var started = false
    private var lastRx = -1L
    private var lastTx = -1L
    private var foldedHour = -1L

    private val file: File get() = File(app.filesDir, FILE_NAME)

    private val tick = object : Runnable {
        override fun run() {
            runCatching { sample() }
            handler.postDelayed(this, SAMPLE_MS)
        }
    }

    @Synchronized
    fun start(context: Context) {
        if (started) return
        started = true
        app = context.applicationContext
        handler.post(tick)
    }

    /** Takes a sample now and returns the file's text (blocking; call off the main thread). */
    fun snapshot(): String {
        val result = java.util.concurrent.FutureTask {
            runCatching { sample() }
            if (file.exists()) file.readText() else ""
        }
        handler.post(result)

        return result.get()
    }

    private fun sample() {
        val uid = Process.myUid()
        val rx = TrafficStats.getUidRxBytes(uid)
        val tx = TrafficStats.getUidTxBytes(uid)
        if (rx < 0 || tx < 0) return // TrafficStats.UNSUPPORTED

        if (OwnVpn.isActive(app) && lastRx >= 0 && rx >= lastRx && tx >= lastTx) {
            val dRx = rx - lastRx
            val dTx = tx - lastTx
            if (dRx + dTx > 0) {
                file.appendText("${currentHour()}\t${serverId()}\t$dRx\t$dTx\n")
            }
        }
        lastRx = rx
        lastTx = tx

        val hour = currentHour()
        if (hour != foldedHour) {
            foldedHour = hour
            fold(hour)
        }
    }

    private fun currentHour(): Long = System.currentTimeMillis() / 1000 / 3600 * 3600

    private fun serverId(): String = app.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        .getString(SERVER_KEY, null)
        ?.replace('\t', ' ')
        ?.replace('\n', ' ')
        ?: ""

    /** One line per hour and server, nothing older than [KEEP_DAYS]. */
    private fun fold(nowHour: Long) {
        if (!file.exists()) return
        val oldest = nowHour - KEEP_DAYS * 24 * 3600
        val totals = LinkedHashMap<Pair<Long, String>, LongArray>()
        file.forEachLine { line ->
            val parts = line.split('\t')
            if (parts.size != 4) return@forEachLine
            val hour = parts[0].toLongOrNull() ?: return@forEachLine
            val rx = parts[2].toLongOrNull() ?: return@forEachLine
            val tx = parts[3].toLongOrNull() ?: return@forEachLine
            if (hour < oldest) return@forEachLine
            val sum = totals.getOrPut(hour to parts[1]) { LongArray(2) }
            sum[0] += rx
            sum[1] += tx
        }
        val tmp = File(app.filesDir, "$FILE_NAME.tmp")
        tmp.bufferedWriter().use { out ->
            for ((key, sum) in totals) out.write("${key.first}\t${key.second}\t${sum[0]}\t${sum[1]}\n")
        }
        tmp.renameTo(file)
    }
}
