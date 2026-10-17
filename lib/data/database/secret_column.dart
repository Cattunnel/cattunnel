import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:drift/drift.dart';

/// Secret database columns (server login and password, the TLS auth key, the
/// subscription URL with its token, the age private key): AES-256-GCM with the
/// key from DbKeyStore, stored as `enc1:<base64(nonce | ciphertext | tag)>`.
/// A value without the prefix is plain text from an older version - read as
/// is and sealed by migration v14 or the next write.
class SecretColumn extends TypeConverter<String, String> {
  const SecretColumn();

  static const _prefix = 'enc1:';
  static final _aes = DartAesGcm.with256bits();
  static final _random = Random.secure();
  static SecretKeyData? _key;

  /// Set once before the database opens (connection.dart).
  static void useKey(Uint8List key) => _key = SecretKeyData(key);

  static bool get ready => _key != null;

  static bool isSealed(String value) => value.startsWith(_prefix);

  static String seal(String plain) {
    final key = _key;
    if (key == null) throw StateError('SecretColumn: no database key');
    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
    final box = _aes.encryptSync(utf8.encode(plain), secretKeyData: key, nonce: nonce);

    return _prefix + base64.encode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  static String open(String stored) {
    if (!isSealed(stored)) return stored;
    final key = _key;
    if (key == null) return '';
    try {
      final raw = base64.decode(stored.substring(_prefix.length));
      final box = SecretBox(
        raw.sublist(12, raw.length - 16),
        nonce: raw.sublist(0, 12),
        mac: Mac(raw.sublist(raw.length - 16)),
      );

      return utf8.decode(_aes.decryptSync(box, secretKeyData: key));
    } on Object {
      // Sealed with a key that is gone (DbKeyStore made a new one).
      return '';
    }
  }

  @override
  String fromSql(String fromDb) => open(fromDb);

  @override
  // Without a key (only an in-memory test database) the value stays plain.
  String toSql(String value) => value.isEmpty || !ready ? value : seal(value);
}
