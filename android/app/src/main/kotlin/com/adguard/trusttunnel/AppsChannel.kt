package com.adguard.trusttunnel

import android.app.Activity
import android.content.Context
import android.content.pm.ApplicationInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.PowerManager
import android.telephony.TelephonyManager
import android.graphics.Bitmap
import android.graphics.Canvas
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * `cattunnel/apps` - installed apps for the per-app split tunneling picker
 * (lib/feature/settings/app_split): every package, system ones included
 * (QUERY_ALL_PACKAGES) - vendor services have no launcher entry but still
 * need to be excludable.
 */
class AppsChannel(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    private val executor = Executors.newSingleThreadExecutor()

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "list" -> background(result) { list() }
            "packages" -> background(result) { packages() }
            "sdkInt" -> result.success(android.os.Build.VERSION.SDK_INT)
            "defaultBrowser" -> background(result) { defaultBrowser() }
            "browsers" -> background(result) { browsers() }
            "deviceInfo" -> background(result) { deviceInfo() }
            "icon" -> {
                val packageName = call.argument<String>("package")!!
                val size = call.argument<Int>("size") ?: 96
                background(result) { icon(packageName, size) }
            }
            else -> result.notImplemented()
        }
    }

    private fun <T> background(result: MethodChannel.Result, block: () -> T) {
        executor.execute {
            try {
                val value = block()
                activity.runOnUiThread { result.success(value) }
            } catch (t: Throwable) {
                activity.runOnUiThread { result.error("apps_error", t.message, null) }
            }
        }
    }

    /** [{package, label, system}] of every installed package, CatTunnel itself left out. */
    private fun list(): List<Map<String, Any>> {
        val pm = activity.packageManager
        return pm.getInstalledApplications(0)
            .filter { it.packageName != activity.packageName }
            .map { info ->
                mapOf(
                    "package" to info.packageName,
                    "label" to pm.getApplicationLabel(info).toString(),
                    "system" to ((info.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                )
            }
    }

    /**
     * Package of the app that opens https links by default (the TLS
     * fingerprint "auto", lib/feature/vpn/domain/tls_profile_auto.dart);
     * null when the user never picked one and Android would ask.
     */
    /**
     * The package that opens https links without asking, or null when the
     * user never picked one. resolveActivity then returns a chooser - "android"
     * on stock Android, a vendor package on some skins - so the answer only
     * counts if it is one of the real https handlers.
     */
    private fun defaultBrowser(): String? {
        val pm = activity.packageManager
        val info = pm.resolveActivity(browserIntent(), android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
        val pkg = info?.activityInfo?.packageName ?: return null
        return if (pkg in browsers()) pkg else null
    }

    /** Every installed app that handles https links, CatTunnel left out. */
    private fun browsers(): List<String> =
        activity.packageManager
            .queryIntentActivities(browserIntent(), android.content.pm.PackageManager.MATCH_ALL)
            .map { it.activityInfo.packageName }
            .filter { it != activity.packageName }
            .distinct()

    private fun browserIntent() =
        android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse("https://example.com/"))
            .addCategory(android.content.Intent.CATEGORY_BROWSABLE)

    /** Package names only: no labels to load, fast enough for every connect. */
    private fun packages(): List<String> =
        activity.packageManager.getInstalledApplications(0)
            .map { it.packageName }
            .filter { it != activity.packageName }

    /**
     * Phone, OS and network facts for the problem report
     * (lib/feature/support/problem_report.dart). Nothing here needs a
     * permission; a part that fails is just left out.
     */
    private fun deviceInfo(): Map<String, Any?> {
        val info = mutableMapOf<String, Any?>(
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
            "model" to Build.MODEL,
            "device" to Build.DEVICE,
            "firmware" to Build.DISPLAY,
            "android" to Build.VERSION.RELEASE,
            "sdk" to Build.VERSION.SDK_INT,
            "securityPatch" to Build.VERSION.SECURITY_PATCH,
            "abi" to Build.SUPPORTED_ABIS.firstOrNull(),
        )
        runCatching {
            val tm = activity.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            info["operator"] = tm.networkOperatorName
            info["operatorCode"] = tm.networkOperator
            info["simOperator"] = tm.simOperatorName
            info["simCountry"] = tm.simCountryIso
            info["roaming"] = tm.isNetworkRoaming
        }
        runCatching {
            val cm = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            // The underlying network, not our own VPN.
            val transports = mutableSetOf<String>()
            var vpnUp = false
            @Suppress("DEPRECATION")
            for (network in cm.allNetworks) {
                val caps = cm.getNetworkCapabilities(network) ?: continue
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                    vpnUp = true
                    continue
                }
                if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) continue
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) transports += "wifi"
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) transports += "mobile"
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) transports += "ethernet"
            }
            info["network"] = transports.sorted().joinToString("+").ifEmpty { "none" }
            info["systemVpnUp"] = vpnUp
            val link = cm.getLinkProperties(cm.activeNetwork)
            if (link != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info["privateDns"] = when {
                    link.privateDnsServerName != null -> link.privateDnsServerName
                    link.isPrivateDnsActive -> "auto"
                    else -> "off"
                }
            }
        }
        runCatching {
            val pm = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
            info["batteryUnrestricted"] = pm.isIgnoringBatteryOptimizations(activity.packageName)
            info["powerSave"] = pm.isPowerSaveMode
        }
        return info
    }

    /** PNG of the app icon, [size] px square; null if the app is gone. */
    private fun icon(packageName: String, size: Int): ByteArray? {
        val drawable = try {
            activity.packageManager.getApplicationIcon(packageName)
        } catch (e: Exception) {
            return null
        }
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(Canvas(bitmap))
        return ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            bitmap.recycle()
            out.toByteArray()
        }
    }

    companion object {
        const val CHANNEL = "cattunnel/apps"
    }
}
