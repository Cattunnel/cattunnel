package com.adguard.trusttunnel

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.content.pm.PackageInfoCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * `cattunnel/update` - native side of the in-app update (lib/feature/updates).
 * Dart downloads the APK into cache/updates/; here it is checked against the
 * sha256 from latest.json, then against our own signing certificate,
 * package name and versionCode, and only then handed to the system
 * installer. The installer itself also refuses an APK signed with a
 * different key; checking here first means a swapped file is deleted with a
 * clear message instead of a system error, and a downgrade is never offered.
 */
class UpdateChannel(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "canInstall" -> result.success(activity.packageManager.canRequestPackageInstalls())
                "openInstallPermission" -> {
                    activity.startActivity(
                        Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
                    )
                    result.success(null)
                }
                "install" -> result.success(install(call.argument<String>("path")!!, call.argument<String>("sha256")!!))
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            result.error("update_error", t.message, null)
        }
    }

    /** "ok", "hash_mismatch", "untrusted" or "no_permission". */
    private fun install(path: String, expectedSha256: String): String {
        val updatesDir = File(activity.cacheDir, "updates").canonicalFile
        val apk = File(path).canonicalFile
        require(apk.parentFile == updatesDir) { "APK outside cache/updates" }

        if (!sha256(apk).equals(expectedSha256.trim(), ignoreCase = true)) {
            apk.delete()
            return "hash_mismatch"
        }
        if (!isTrustedUpdate(apk)) {
            apk.delete()
            return "untrusted"
        }
        if (!activity.packageManager.canRequestPackageInstalls()) return "no_permission"

        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", apk)
        activity.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        )
        return "ok"
    }

    /**
     * Same package, a newer versionCode, and every signer of the APK is one
     * of ours. When Android can't read the archive's signers at all (seen on
     * some 8.x builds) the decision is left to the installer, which enforces
     * the same-key rule for updates anyway.
     */
    private fun isTrustedUpdate(apk: File): Boolean {
        val pm = activity.packageManager
        val flags = signatureFlags()
        val own = pm.getPackageInfo(activity.packageName, flags)
        val update = pm.getPackageArchiveInfo(apk.path, flags) ?: return false

        if (update.packageName != activity.packageName) return false
        if (PackageInfoCompat.getLongVersionCode(update) <= PackageInfoCompat.getLongVersionCode(own)) return false

        val updateSigners = signers(update, current = true) ?: return true
        val ownSigners = signers(own, current = false) ?: return false
        return updateSigners.isNotEmpty() && ownSigners.containsAll(updateSigners)
    }

    @Suppress("DEPRECATION")
    private fun signatureFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) PackageManager.GET_SIGNING_CERTIFICATES
        else PackageManager.GET_SIGNATURES

    /**
     * SHA-256 of the signing certificates, or null if Android didn't report
     * them. For our installed app [current] = false also takes the rotation
     * history, so a future key rotation still accepts updates.
     */
    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo, current: Boolean): Set<String>? {
        val certs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signing = info.signingInfo ?: return null
            when {
                signing.hasMultipleSigners() -> signing.apkContentsSigners
                current -> signing.signingCertificateHistory?.takeLast(1)?.toTypedArray()
                else -> signing.signingCertificateHistory
            }
        } else {
            info.signatures
        } ?: return null
        if (certs.isEmpty()) return null
        return certs.map { sha256(it.toByteArray()) }.toSet()
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    companion object {
        const val CHANNEL = "cattunnel/update"
    }
}
