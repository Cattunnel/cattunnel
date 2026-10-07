package com.adguard.trusttunnel

import android.app.Activity
import android.app.ActivityManager
import android.app.KeyguardManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.Inet6Address
import java.security.KeyStore
import java.security.cert.X509Certificate

/**
 * `cattunnel/security` - native side of the Cyber security section and
 * Marsik's phone checklist / leak check (see lib/feature/security).
 */
class SecurityChannel(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "systemCaBundle" -> result.success(systemCaBundle())
                "certificateReport" -> result.success(certificateReport())
                "deviceReport" -> result.success(deviceReport())
                "vpnNetworkReport" -> result.success(vpnNetworkReport())
                "openSettings" -> result.success(openSettings(call.arguments as String))
                "isDisguised" -> result.success(isDisguised())
                "setDisguised" -> {
                    setDisguised(call.arguments == true)
                    result.success(null)
                }
                "wipeAllData" -> {
                    result.success(null)
                    wipeAllData()
                }
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            result.error("security_error", t.message, null)
        }
    }

    // --- Certificates -----------------------------------------------------

    private fun caStore(): KeyStore = KeyStore.getInstance("AndroidCAStore").apply { load(null, null) }

    private fun isRussianTrusted(cert: X509Certificate): Boolean =
        RUSSIAN_TRUSTED_MARKERS.any { cert.subjectX500Principal.name.contains(it, ignoreCase = true) }

    /**
     * PEM of every *system* root except the Russian Ministry of Digital
     * Development ones. Handed to the VPN engine as the endpoint CA store when
     * a server has no certificate of its own, so a user-installed (or
     * vendor-preinstalled) Russian Trusted CA can never vouch for a forged
     * endpoint certificate. Built from the device's live store, so Android
     * CA updates flow through on the next connect.
     */
    private fun systemCaBundle(): String {
        val store = caStore()
        val out = StringBuilder()
        for (alias in store.aliases()) {
            if (!alias.startsWith("system:")) continue
            val cert = store.getCertificate(alias) as? X509Certificate ?: continue
            if (isRussianTrusted(cert)) continue
            out.append("-----BEGIN CERTIFICATE-----\n")
            out.append(Base64.encodeToString(cert.encoded, Base64.DEFAULT))
            out.append("-----END CERTIFICATE-----\n")
        }
        return out.toString()
    }

    /** User-installed CAs, plus any Russian Trusted CA found among system ones. */
    private fun certificateReport(): List<Map<String, Any>> {
        val store = caStore()
        val report = mutableListOf<Map<String, Any>>()
        for (alias in store.aliases()) {
            val cert = store.getCertificate(alias) as? X509Certificate ?: continue
            val user = alias.startsWith("user:")
            val russian = isRussianTrusted(cert)
            if (!user && !russian) continue
            report += mapOf(
                "subject" to cert.subjectX500Principal.name,
                "user" to user,
                "russianTrusted" to russian,
            )
        }
        return report
    }

    // --- Device checks ------------------------------------------------------

    private fun deviceReport(): Map<String, Any?> {
        val keyguard = activity.getSystemService(KeyguardManager::class.java)
        val power = activity.getSystemService(PowerManager::class.java)
        val resolver = activity.contentResolver

        return mapOf(
            "deviceSecure" to (keyguard?.isDeviceSecure ?: false),
            "privateDnsMode" to Settings.Global.getString(resolver, "private_dns_mode"),
            "privateDnsHost" to Settings.Global.getString(resolver, "private_dns_specifier"),
            "adbEnabled" to (Settings.Global.getInt(resolver, Settings.Global.ADB_ENABLED, 0) == 1),
            "batteryOptimizationIgnored" to (power?.isIgnoringBatteryOptimizations(activity.packageName) ?: false),
        )
    }

    /**
     * Routes and DNS of the VPN network, and whether the underlying network
     * has global IPv6 - a VPN without a ::/0 route on such a network leaks all
     * IPv6 traffic around the tunnel. Also whether Android validated our VPN
     * network (some firmwares, BBK's in particular, then report "no VPN" /
     * "no internet" although the tunnel works) and who made the phone.
     */
    @Suppress("DEPRECATION")
    private fun vpnNetworkReport(): Map<String, Any?> {
        val connectivity = activity.getSystemService(ConnectivityManager::class.java)
            ?: return mapOf("vpnActive" to false)

        var vpnActive = false
        var defaultV4 = false
        var defaultV6 = false
        var dns = listOf<String>()
        var underlyingGlobalV6 = false
        var vpnValidated: Boolean? = null

        for (network in connectivity.allNetworks) {
            val caps = connectivity.getNetworkCapabilities(network) ?: continue
            val link = connectivity.getLinkProperties(network) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                vpnActive = true
                // Only ours: another app's VPN says nothing about CatTunnel.
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || caps.ownerUid == android.os.Process.myUid()) {
                    vpnValidated = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                }
                for (route in link.routes) {
                    val destination = route.destination
                    if (destination.prefixLength != 0) continue
                    if (destination.address is Inet6Address) defaultV6 = true else defaultV4 = true
                }
                dns = link.dnsServers.mapNotNull { it.hostAddress }
            } else if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                underlyingGlobalV6 = underlyingGlobalV6 || link.linkAddresses.any {
                    val address = it.address
                    address is Inet6Address && !address.isLinkLocalAddress && !address.isSiteLocalAddress &&
                        !address.isLoopbackAddress && (address.address[0].toInt() and 0xfe) != 0xfc
                }
            }
        }

        return mapOf(
            "vpnActive" to vpnActive,
            "defaultRouteV4" to defaultV4,
            "defaultRouteV6" to defaultV6,
            "vpnDnsServers" to dns,
            "underlyingHasGlobalIpv6" to underlyingGlobalV6,
            "vpnValidated" to vpnValidated,
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
        )
    }

    private fun openSettings(target: String): Boolean {
        val intent = when (target) {
            "vpn" -> Intent(Settings.ACTION_VPN_SETTINGS)
            "security" -> Intent(Settings.ACTION_SECURITY_SETTINGS)
            "network" -> Intent(Settings.ACTION_WIRELESS_SETTINGS)
            "developer" -> Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
            // The per-app REQUEST_IGNORE_BATTERY_OPTIMIZATIONS dialog needs a
            // manifest permission; the list screen doesn't.
            "battery" -> Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            "lock" -> Intent(Settings.ACTION_SECURITY_SETTINGS)
            else -> return false
        }

        return try {
            activity.startActivity(intent)
            true
        } catch (_: Throwable) {
            // Some OEM builds lack the specific screen - fall back to Settings.
            try {
                activity.startActivity(Intent(Settings.ACTION_SETTINGS))
                true
            } catch (_: Throwable) {
                false
            }
        }
    }

    // --- Disguise -----------------------------------------------------------

    private fun component(alias: String) = ComponentName(activity.packageName, "com.adguard.trusttunnel.$alias")

    private fun isDisguised(): Boolean =
        activity.packageManager.getComponentEnabledSetting(component(ALIAS_DISGUISED)) ==
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED

    /** Swaps the launcher entry between CatTunnel and the "Calculator" alias. */
    private fun setDisguised(disguised: Boolean) {
        val pm = activity.packageManager
        val on = PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        val off = PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        pm.setComponentEnabledSetting(component(ALIAS_DISGUISED), if (disguised) on else off, PackageManager.DONT_KILL_APP)
        pm.setComponentEnabledSetting(component(ALIAS_DEFAULT), if (disguised) off else on, PackageManager.DONT_KILL_APP)
    }

    // --- Panic wipe ---------------------------------------------------------

    /**
     * Stops the tunnel, then has the system wipe everything the app owns -
     * database, preferences, files, logs - and kill the process, exactly like
     * "Clear data" in app settings. Launcher disguise (a component setting,
     * not app data) survives on purpose.
     */
    private fun wipeAllData() {
        try {
            VpnService.stop(activity.applicationContext)
        } catch (_: Throwable) {
        }
        activity.getSystemService(ActivityManager::class.java)?.clearApplicationUserData()
    }

    companion object {
        private const val CHANNEL = "cattunnel/security"
        const val ALIAS_DEFAULT = "MainActivity"
        const val ALIAS_DISGUISED = "LauncherCalculator"

        /** Subject markers of the Russian Ministry of Digital Development CAs. */
        private val RUSSIAN_TRUSTED_MARKERS = listOf("Russian Trusted Root CA", "Russian Trusted Sub CA")
    }
}
