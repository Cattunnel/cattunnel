package com.adguard.trusttunnel

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * `cattunnel/keystore` - wraps the database key (lib/data/database/db_key_store.dart)
 * with an AES-GCM key that lives in the Android Keystore and never leaves it, so a
 * copy of the app's files alone doesn't open the secret columns.
 */
class KeystoreChannel(messenger: BinaryMessenger) {

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                val data = call.arguments as ByteArray
                when (call.method) {
                    "wrap" -> result.success(wrap(data))
                    "unwrap" -> result.success(unwrap(data))
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("keystore", e.message, null)
            }
        }
    }

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    /** iv (12) + ciphertext with tag */
    private fun wrap(plain: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        return cipher.iv + cipher.doFinal(plain)
    }

    private fun unwrap(wrapped: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, wrapped, 0, 12))
        return cipher.doFinal(wrapped, 12, wrapped.size - 12)
    }

    companion object {
        const val CHANNEL = "cattunnel/keystore"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val ALIAS = "cattunnel_db_key"
    }
}
