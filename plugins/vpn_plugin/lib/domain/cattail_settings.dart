import 'dart:convert';

/// CatTail, the noisy disguise (~/oc/cattail.md, subscription tags
/// 0x56-0x59): the checks of its settings shared by the link codec, the
/// engine config and the server form.
abstract final class CattailSettings {
  /// At most this many ports or ranges in 0x57.
  static const maxPortParts = 16;

  /// The padding scheme of 0x59 is short text, a few lines.
  static const maxPatternLength = 2048;

  /// The limits of the endpoint's parser (PaddingScheme::parse).
  static const maxStop = 16;
  static const maxItems = 16;
  static const maxSteadyPadding = 4096;
  static const maxNonce = 24;

  /// The whole size of one frame on the wire: header and tag around 0..16384 bytes of body.
  static const minFrame = 48;
  static const maxFrame = 16448;

  static final _range = RegExp(r'^(\d{1,5})(?:-(\d{1,5}))?$');

  /// `20000-40000`, `443` or a list of them (commas or spaces) to the
  /// form `20000-40000,443`; null when a port is outside 1..65535, a
  /// range is reversed or the list is empty or too long.
  static String? normalizePorts(String raw) {
    final parts = raw.split(RegExp(r'[\s,;]+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty || parts.length > maxPortParts) return null;
    final out = <String>[];
    for (final part in parts) {
      final match = _range.firstMatch(part);
      if (match == null) return null;
      final low = int.parse(match.group(1)!);
      final high = match.group(2) == null ? low : int.parse(match.group(2)!);
      if (low < 1 || high > 65535 || low > high) return null;
      final text = low == high ? '$low' : '$low-$high';
      if (!out.contains(text)) out.add(text);
    }
    return out.join(',');
  }

  /// The endpoint key: base64 of 32 bytes, the same form as the NineLives
  /// key (ConfigurationCodecKeys.isValidXhttpServerKey).
  static bool isValidKey(String key) {
    if (key.length != 44) return false;
    try {
      return base64Decode(key).length == 32;
    } on FormatException {
      return false;
    }
  }

  /// The key from tag 0x58: 32 raw bytes, or the same in base64 text.
  static String keyFromTag(List<int> value) {
    if (value.length == 32) return base64Encode(value);
    try {
      final text = utf8.decode(value).trim();
      return isValidKey(text) ? text : '';
    } on FormatException {
      return '';
    }
  }

  /// The padding scheme, the way the endpoint reads it (server
  /// docs/cattail.md section 4.1, PaddingScheme::parse): lines split by a
  /// new line or `;`, `key=value`, spaces ignored.
  ///
  /// - `stop`: one number 0..16;
  /// - `0`..`15`: up to 16 items, each `lo-hi` or `n` (the whole size of a
  ///   frame on the wire, 48..16448) or `c`;
  /// - `mid`, `end`: `lo-hi` or `n`, 0..4096; `nonce`: 0..24;
  /// - any other key is skipped.
  ///
  /// Returns the scheme in a clean form (known keys only). Empty stays empty
  /// (the engine default); one wrong line makes the whole scheme null.
  static String? normalizePattern(String raw) {
    if (raw.length > maxPatternLength) return null;
    final out = <String>[];
    for (final part in raw.split(RegExp(r'[\n;]'))) {
      final line = part.replaceAll('\r', '').trim();
      if (line.isEmpty) continue;
      final equals = line.indexOf('=');
      if (equals < 0) return null;
      final key = line.substring(0, equals).trim();
      final value = line.substring(equals + 1).trim();
      switch (key) {
        case 'stop':
          final range = _bounds(value, 0, maxStop);
          if (range == null || range.$1 != range.$2) return null;
          out.add('stop=${range.$1}');
        case 'mid' || 'end' || 'nonce':
          final range = _bounds(value, 0, key == 'nonce' ? maxNonce : maxSteadyPadding);
          if (range == null) return null;
          out.add('$key=${_text(range)}');
        case _ when RegExp(r'^\d+$').hasMatch(key):
          final index = int.tryParse(key);
          if (index == null || index >= maxStop) return null;
          final items = value.split(',').map((item) => item.trim()).toList();
          if (items.length > maxItems) return null;
          final text = <String>[];
          for (final item in items) {
            if (item == 'c') {
              text.add('c');
              continue;
            }
            final range = _bounds(item, minFrame, maxFrame);
            if (range == null) return null;
            text.add(_text(range));
          }
          out.add('$index=${text.join(',')}');
        default:
          break;
      }
    }
    return out.join('\n');
  }

  static (int, int)? _bounds(String value, int min, int max) {
    final match = RegExp(r'^(\d{1,6})\s*(?:-\s*(\d{1,6}))?$').firstMatch(value);
    if (match == null) return null;
    final low = int.parse(match.group(1)!);
    final high = match.group(2) == null ? low : int.parse(match.group(2)!);
    return low <= high && low >= min && high <= max ? (low, high) : null;
  }

  static String _text((int, int) range) => range.$1 == range.$2 ? '${range.$1}' : '${range.$1}-${range.$2}';
}
