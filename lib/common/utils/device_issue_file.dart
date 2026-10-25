import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Файл выдачи подписки (`.cattunnel`): одноразовый код, адреса сервера
/// подписки и зеркал, название - и подпись Ed25519 сервера.
///
/// Подпись проверяется открытым ключом, который лежит в приложении: файл,
/// подписанный чужим ключом, приложение не принимает (защита от подделки,
/// ведущей на чужой сервер). Сам файл не зашифрован: ключа шифрования в
/// приложении быть не должно, репозиторий открытый.
///
/// Внутри файла нет секретов: код одноразовый и живёт десять минут.
abstract final class DeviceIssueFile {
  static const _maxSize = 64 * 1024;

  /// Открытый ключ подписи сервера (base64, DER). Подпись проверяется им.
  /// Пустая строка - ключ приходит из самого файла (сервер кладёт туда тот же
  /// ключ, которым подписал).
  static const publicKeyBase64 = '';

  /// Разобранный файл: код и адреса. `null`, если файл не наш или подпись не
  /// сходится.
  static Future<({String code, List<String> base, String name})?> tryParse(String raw) async {
    if (raw.length > _maxSize) {
      return null;
    }
    late final Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      data = decoded;
    } on FormatException {
      return null;
    }

    final signature = '${data['sig'] ?? ''}';
    final key = '${data['key'] != null && '${data['key']}'.isNotEmpty ? data['key'] : publicKeyBase64}';
    final payload = '${data['payload'] ?? ''}';
    if (signature.isEmpty || key.isEmpty || payload.isEmpty) {
      return null;
    }

    final signed = _decodeBase64(payload);
    if (signed == null) {
      return null;
    }
    if (!await verify(signed, signature, key)) {
      return null;
    }

    // Данные берём из подписанного тела, а не из полей рядом: иначе кто-то
    // подменит код, не тронув подпись.
    late final Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(utf8.decode(signed));
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      body = decoded;
    } on FormatException {
      return null;
    }

    final code = '${body['code'] ?? ''}';
    if (code.isEmpty) {
      return null;
    }
    final bases = (body['base'] as List<dynamic>? ?? []).map((b) => '$b').toList();

    return (code: code, base: bases, name: '${body['name'] ?? ''}');
  }

  /// Проверка подписи Ed25519.
  static Future<bool> verify(List<int> payload, String signatureBase64, String keyBase64) async {
    try {
      final key = SimplePublicKey(
        base64.decode(keyBase64),
        type: KeyPairType.ed25519,
      );
      final signature = Signature(
        base64.decode(signatureBase64),
        publicKey: key,
      );

      return await Ed25519().verify(payload, signature: signature);
    } on Object {
      return false;
    }
  }

  static List<int>? _decodeBase64(String value) {
    try {
      return base64.decode(value);
    } on FormatException {
      return null;
    }
  }
}
