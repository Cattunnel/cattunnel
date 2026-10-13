package com.adguard.trusttunnel

import android.content.Context
import android.net.TrafficStats
import android.os.Handler
import android.os.HandlerThread
import android.os.Process
import java.io.File
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit

/**
 * The app's own traffic statistics (Settings -> Traffic statistics), kept
 * on the phone only.
 *
 * While our VPN service is up (or was at the last sample), every
 * [ACTIVE_MS] the bytes this app's UID sent and received since the last
 * sample (TrafficStats - the engine's sockets to the server are ours, so
 * this is the tunnel's traffic on the wire, encryption included) are added
 * to the current hour and the current server (the id the app keeps as the
 * last picked one). With the VPN off it only looks every [IDLE_MS] - the
 * counters are cumulative, so nothing is lost when it starts in between.
 *
 * Two files in filesDir, lines `hourEpochSec<TAB>serverId<TAB>rx<TAB>tx`:
 * - `traffic_pending.tsv` - raw samples of the hours not folded yet (small);
 * - `traffic_hourly.tsv` - one line per finished hour and server, only ever
 *   appended to; trimmed to [KEEP_DAYS] once a day.
 * Dart reads both through [TrafficChannel] (summing duplicates, skipping a
 * torn line); `clear` deletes them.
 *
 * All work happens on its own thread.
 */
object TrafficRecorder {
    private const val ARCHIVE = "traffic_hourly.tsv"
    private const val PENDING = "traffic_pending.tsv"
    private const val ACTIVE_MS = 30_000L
    private const val IDLE_MS = 5 * 60_000L

    /** 90-day charts compare with the 90 days before. */
    private const val KEEP_DAYS = 180L
    private const val SERVER_KEY = "flutter.auto_connect_on_launch_last_server_id"

    private val thread = HandlerThread("cattunnel-traffic").apply { start() }
    private val handler = Handler(thread.looper)

    private lateinit var app: Context
    private var started = false
    private var lastRx = -1L
    private var lastTx = -1L
    private var wasActive = false
    private var foldedHour = -1L
    private var trimmedDay = -1L

    private fun file(name: String) = File(app.filesDir, name)

    private val tick = object : Runnable {
        override fun run() {
            val active = runCatching { sample() }.getOrDefault(false)
            handler.postDelayed(this, if (active) ACTIVE_MS else IDLE_MS)
        }
    }

    @Synchronized
    fun start(context: Context) {
        if (started) return
        started = true
        app = context.applicationContext
        handler.post(tick)
    }

    /** Takes a sample now and returns both files' text (blocking; call off the main thread). */
    fun snapshot(): String = onRecorderThread {
        runCatching { sample() }
        listOf(ARCHIVE, PENDING).joinToString("") { name ->
            file(name).let { if (it.exists()) it.readText() else "" }
        }
    }

    /** Forgets all statistics. */
    fun clear() {
        onRecorderThread {
            file(ARCHIVE).delete()
            file(PENDING).delete()
            file("$ARCHIVE.tmp").delete()
            file("$PENDING.tmp").delete()
        }
    }

    private fun <T> onRecorderThread(block: () -> T): T {
        val task = FutureTask(block)
        handler.post(task)

        return task.get(10, TimeUnit.SECONDS)
    }

    /** Returns whether the VPN is up now. */
    private fun sample(): Boolean {
        val active = OwnVpn.isActive(app)
        val uid = Process.myUid()
        val rx = TrafficStats.getUidRxBytes(uid)
        val tx = TrafficStats.getUidTxBytes(uid)
        if (rx < 0 || tx < 0) return active // TrafficStats.UNSUPPORTED

        // Up now or at the last sample: a VPN that stopped in between still
        // carried that traffic (the app's own few requests around a start
        // or stop are the price).
        if ((active || wasActive) && lastRx >= 0 && rx >= lastRx && tx >= lastTx) {
            val dRx = rx - lastRx
            val dTx = tx - lastTx
            if (dRx + dTx > 0) {
                file(PENDING).appendText("${currentHour()}\t${serverId()}\t$dRx\t$dTx\n")
            }
        }
        lastRx = rx
        lastTx = tx
        wasActive = active

        val hour = currentHour()
        if (hour != foldedHour && foldPending(hour)) foldedHour = hour
        val day = hour / 86_400
        if (day != trimmedDay && trimArchive(hour)) trimmedDay = day

        return active
    }

    private fun currentHour(): Long = System.currentTimeMillis() / 1000 / 3600 * 3600

    private fun serverId(): String = app.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        .getString(SERVER_KEY, null)
        ?.replace(Regex("[\\t\\r\\n]"), " ")
        ?: ""

    private fun readTotals(file: File, keep: (Long) -> Boolean): LinkedHashMap<Pair<Long, String>, LongArray> {
        val totals = LinkedHashMap<Pair<Long, String>, LongArray>()
        if (!file.exists()) return totals
        file.forEachLine { line ->
            val parts = line.split('\t')
            if (parts.size != 4) return@forEachLine
            val hour = parts[0].toLongOrNull() ?: return@forEachLine
            val rx = parts[2].toLongOrNull() ?: return@forEachLine
            val tx = parts[3].toLongOrNull() ?: return@forEachLine
            if (!keep(hour)) return@forEachLine
            val sum = totals.getOrPut(hour to parts[1]) { LongArray(2) }
            sum[0] += rx
            sum[1] += tx
        }

        return totals
    }

    private fun write(file: File, totals: Map<Pair<Long, String>, LongArray>): Boolean {
        val tmp = File(file.parentFile, "${file.name}.tmp")
        tmp.bufferedWriter().use { out ->
            for ((key, sum) in totals) out.write("${key.first}\t${key.second}\t${sum[0]}\t${sum[1]}\n")
        }
        if (tmp.renameTo(file)) return true
        tmp.delete()

        return false
    }

    /** Finished hours of the pending file go to the archive (appended); the current hour stays. */
    private fun foldPending(nowHour: Long): Boolean {
        val pending = file(PENDING)
        if (!pending.exists()) return true
        val finished = readTotals(pending) { it < nowHour }
        if (finished.isNotEmpty()) {
            file(ARCHIVE).appendText(
                finished.entries.joinToString("") { (key, sum) -> "${key.first}\t${key.second}\t${sum[0]}\t${sum[1]}\n" },
            )
        }

        return write(pending, readTotals(pending) { it >= nowHour })
    }

    /** Once a day: nothing older than [KEEP_DAYS], one line per hour and server. */
    private fun trimArchive(nowHour: Long): Boolean {
        val archive = file(ARCHIVE)
        if (!archive.exists()) return true
        val oldest = nowHour - KEEP_DAYS * 24 * 3600

        return write(archive, readTotals(archive) { it >= oldest })
    }
}
