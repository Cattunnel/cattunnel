import 'dart:convert';

/// The engine's ping of the endpoint it picked (item 13, 1.5.9.5). Android
/// forwards the milliseconds (PingRecord.kt); a platform that hands over the
/// engine record itself sends `{"cattunnel_ping_ms":N}`. Both read here.
abstract final class TunnelPing {
  /// The same bound as PingRecord.MAX_MS on Android.
  static const maxMs = 60000;

  /// Milliseconds, or null for anything that is not a ping in range.
  static int? fromValue(Object? raw) {
    final value = switch (raw) {
      final int ms => ms,
      final String text => _fromRecord(text),
      _ => null,
    };
    return value != null && value >= 0 && value <= maxMs ? value : null;
  }

  static int? _fromRecord(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded.length == 1 && decoded['cattunnel_ping_ms'] is int) {
        return decoded['cattunnel_ping_ms'] as int;
      }
    } on FormatException {
      // Not a record.
    }
    return null;
  }
}
