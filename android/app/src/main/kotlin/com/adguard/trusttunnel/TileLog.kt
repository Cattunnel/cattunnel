package com.adguard.trusttunnel

import android.content.Context
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The tile's connect steps, to logcat and to a small file in filesDir
 * (`tile.log`, last ~32 KB) - some firmwares drop an app's logcat lines
 * right after its process starts, exactly when the tile path runs. No
 * server names, addresses or keys are written here.
 */
object TileLog {
    private const val TAG = "CatTunnelTile"
    private const val MAX_BYTES = 32 * 1024

    fun i(context: Context, message: String) {
        Log.w(TAG, message)
        runCatching {
            val file = File(context.applicationContext.filesDir, "tile.log")
            if (file.length() > MAX_BYTES) file.writeText(file.readText().takeLast(MAX_BYTES / 2))
            val time = SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US).format(Date())
            file.appendText("$time $message\n")
        }
    }
}
