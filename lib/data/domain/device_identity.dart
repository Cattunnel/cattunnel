import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:dage/dage.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

/// Ключ устройства: свой age-ключ X25519 и идентификатор устройства.
///
/// Приложение создаёт ключ при первом запуске и больше не меняет его. Закрытый
/// ключ не покидает устройство: сервер знает только открытый (`age1...`) и
/// отвечает под ним, поэтому утёкшая ссылка или адрес подписки новому
/// устройству ничего не дают.
///
/// Хранение закрытого ключа - как у ключа базы (lib/data/database/db_key_store.dart):
/// Android - AES-GCM ключом из Android Keystore (неизвлекаемым), Windows -
/// DPAPI, Linux - файл с правами 0600.
class DeviceIdentity {
  const DeviceIdentity({
    required this.publicKey,
    required this.privateKey,
    required this.id,
    required this.os,
    required this.model,
    required this.osVersion,
  });

  /// Открытый age-ключ устройства (`age1...`) - он уходит в заголовке
  /// `x-device-key`.
  final String publicKey;

  /// Закрытый ключ устройства (`AGE-SECRET-KEY-1...`). Не покидает устройство:
  /// им расшифровывается ответ подписки, зашифрованный под открытый ключ.
  final String privateKey;

  /// Идентификатор устройства (случайный UUID). Только метка: секретом не
  /// является, защищает от повторной регистрации того же ключа.
  final String id;

  /// Платформа: Android, Windows, Linux, macOS.
  final String os;

  /// Модель устройства (если система её знает).
  final String model;

  /// Версия ОС (если система её знает).
  final String osVersion;

  static const _channel = MethodChannel('cattunnel/keystore');

  static DeviceIdentity? _cached;

  /// Ключ устройства (создаётся при первом запуске).
  static Future<DeviceIdentity> load() async {
    if (_cached != null) return _cached!;

    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/device_identity');

    String? privateKey;
    String? id;
    if (await file.exists()) {
      try {
        final raw = await _unlock(await file.readAsBytes());
        final data = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
        privateKey = data['key'] as String?;
        id = data['id'] as String?;
      } on Object catch (e) {
        debugPrint('DeviceIdentity: the stored key can not be unlocked, making a new one: $e');
      }
    }

    if (privateKey == null || privateKey.isEmpty || id == null || id.isEmpty) {
      final identity = _newIdentity();
      privateKey = identity.toString();
      id = _newUuid();
      final data = jsonEncode({'key': privateKey, 'id': id});
      final locked = await _lock(Uint8List.fromList(utf8.encode(data)));
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(locked, flush: true);
      if (Platform.isLinux || Platform.isMacOS) {
        await Process.run('chmod', ['600', tmp.path]);
      }
      await tmp.rename(file.path);
    }

    final publicKey = await _publicKeyOf(privateKey);
    final platform = await _platformInfo();
    _cached = DeviceIdentity(
      publicKey: publicKey,
      privateKey: privateKey,
      id: id,
      os: platform.os,
      model: platform.model,
      osVersion: platform.osVersion,
    );

    return _cached!;
  }

  /// Заголовки запроса подписки: по ним сервер знает, кто пришёл.
  Map<String, String> get subscriptionHeaders => {
    'x-device-key': publicKey,
    'x-hwid': id,
    'x-device-os': os,
    'x-device-model': model,
    'x-ver-os': osVersion,
    'x-app-version': _appVersion,
  };

  static String _appVersion = '';

  /// Версия приложения (для заголовка x-app-version).
  static Future<void> setAppVersion(String version) async {
    _appVersion = version;
  }

  /// Открытый ключ из закрытого: age устроен так, что публичная часть -
  /// это X25519 от приватной, dage считает это через плагин.
  static Future<String> _publicKeyOf(String privateKey) async {
    final pair = await AgePlugin.convertIdentityToKeyPair(AgeIdentity.fromBech32(privateKey));

    return pair.recipient.toString();
  }

  /// Новая age-идентичность X25519 (32 байта из системного генератора).
  static AgeIdentity _newIdentity() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));

    return AgeIdentity('AGE-SECRET-KEY-', bytes);
  }

  static String _newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Future<({String os, String model, String osVersion})> _platformInfo() async {
    if (Platform.isAndroid) {
      return (os: 'Android', model: '', osVersion: Platform.operatingSystemVersion);
    }
    if (Platform.isWindows) {
      return (os: 'Windows', model: '', osVersion: Platform.operatingSystemVersion);
    }
    if (Platform.isMacOS) {
      return (os: 'macOS', model: '', osVersion: Platform.operatingSystemVersion);
    }

    return (os: 'Linux', model: '', osVersion: Platform.operatingSystemVersion);
  }

  static Future<Uint8List> _lock(Uint8List data) async {
    if (Platform.isAndroid) return (await _channel.invokeMethod<Uint8List>('wrap', data))!;
    if (Platform.isWindows) return _dpapi(data, protect: true);

    return data;
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
