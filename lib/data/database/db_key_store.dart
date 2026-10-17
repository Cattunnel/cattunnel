import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

/// The key of the secret database columns (SecretColumn): 32 random bytes,
/// kept next to the database only in a form the system unlocks for this app:
///
/// - Android: wrapped by an AES-GCM key in the Android Keystore
///   (`cattunnel/keystore`, KeystoreChannel.kt), which never leaves it;
/// - Windows: DPAPI (CryptProtectData), bound to the user account;
/// - Linux: a file with mode 0600 - there is no system key store every
///   desktop has (libsecret needs a running keyring), so here it only keeps
///   the secrets out of a copied database file, not from this user.
abstract final class DbKeyStore {
  static const _channel = MethodChannel('cattunnel/keystore');

  /// The key, created on the first run. If the stored one can't be unlocked
  /// any more (the Keystore key is gone), a new key replaces it: the values
  /// sealed with the old one read empty, and subscriptions fill them again on
  /// the next refresh.
  static Future<Uint8List> load(File keyFile) async {
    if (await keyFile.exists()) {
      try {
        return await _unlock(await keyFile.readAsBytes());
      } on Object catch (e) {
        debugPrint('DbKeyStore: the database key can not be unlocked, making a new one: $e');
        await keyFile.rename('${keyFile.path}.unreadable');
      }
    }
    final random = Random.secure();
    final key = Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
    final locked = await _lock(key);
    final tmp = File('${keyFile.path}.tmp');
    await tmp.writeAsBytes(locked, flush: true);
    if (Platform.isLinux || Platform.isMacOS) {
      await Process.run('chmod', ['600', tmp.path]);
    }
    // Another engine of the app (the tile's) may have made one meanwhile: keep that.
    if (await keyFile.exists()) {
      await tmp.delete();

      return _unlock(await keyFile.readAsBytes());
    }
    await tmp.rename(keyFile.path);

    return key;
  }

  static Future<Uint8List> _lock(Uint8List key) async {
    if (Platform.isAndroid) return (await _channel.invokeMethod<Uint8List>('wrap', key))!;
    if (Platform.isWindows) return _dpapi(key, protect: true);

    return key;
  }

  static Future<Uint8List> _unlock(Uint8List stored) async {
    if (Platform.isAndroid) return (await _channel.invokeMethod<Uint8List>('unwrap', stored))!;
    if (Platform.isWindows) return _dpapi(stored, protect: false);

    return stored;
  }

  static Uint8List _dpapi(Uint8List data, {required bool protect}) {
    const uiForbidden = 0x1; // CRYPTPROTECT_UI_FORBIDDEN
    final input = calloc<CRYPT_INTEGER_BLOB>();
    final output = calloc<CRYPT_INTEGER_BLOB>();
    final bytes = calloc<Uint8>(data.length);
    try {
      bytes.asTypedList(data.length).setAll(0, data);
      input.ref
        ..cbData = data.length
        ..pbData = bytes;
      final ok = protect
          ? CryptProtectData(input, nullptr, nullptr, nullptr, nullptr, uiForbidden, output)
          : CryptUnprotectData(input, nullptr, nullptr, nullptr, nullptr, uiForbidden, output);
      if (ok == 0) throw StateError('DPAPI failed: ${GetLastError()}');
      final result = Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData));
      LocalFree(output.ref.pbData);

      return result;
    } finally {
      free(bytes);
      free(input);
      free(output);
    }
  }
}
