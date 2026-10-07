import 'dart:convert';
import 'dart:typed_data';

/// ASCII armor for age files (age-encryption.org/v1 spec, "ASCII armor"
/// section): standard padded base64 of the binary file, wrapped at 64
/// columns between fixed BEGIN/END lines.
///
/// The vendored `dage` package only reads the binary format, so armored
/// payloads are unwrapped here before decryption.
abstract final class AgeArmor {
  static const _begin = '-----BEGIN AGE ENCRYPTED FILE-----';
  static const _end = '-----END AGE ENCRYPTED FILE-----';

  /// Whether [bytes] look like an armored age file (leading whitespace is
  /// allowed, per the spec).
  static bool isArmored(Uint8List bytes) {
    var start = 0;
    while (start < bytes.length && _isWhitespace(bytes[start])) {
      start++;
    }

    if (bytes.length - start < _begin.length) {
      return false;
    }

    return ascii.decode(bytes.sublist(start, start + _begin.length), allowInvalid: true) == _begin;
  }

  /// Unwraps an armored age file into its binary form.
  ///
  /// Throws [FormatException] if the armor is malformed.
  static Uint8List decode(Uint8List bytes) {
    final lines = ascii
        .decode(bytes)
        .trim()
        .split('\n')
        .map((line) => line.endsWith('\r') ? line.substring(0, line.length - 1) : line)
        .toList();

    if (lines.length < 3 || lines.first != _begin || lines.last != _end) {
      throw const FormatException('Invalid age armor: missing BEGIN/END lines');
    }

    final body = lines.sublist(1, lines.length - 1);
    for (var i = 0; i < body.length; i++) {
      final isLast = i == body.length - 1;
      if (body[i].length > 64 || (!isLast && body[i].length != 64) || body[i].isEmpty) {
        throw const FormatException('Invalid age armor: bad line length');
      }
    }

    return base64.decode(body.join());
  }

  static bool _isWhitespace(int byte) => byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D;
}
