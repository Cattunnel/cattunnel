/// The custom anti-DPI split the engine takes as `anti_dpi_desync` (patch
/// 0001-anti-dpi-desync, `desync_plan_parse` in net/src/tcp_socket.cpp):
/// byedpi syntax, e.g. `-o1+s -d3+s`. The engine rejects the whole endpoint
/// on a bad string, so the app checks it with the same rules first.
abstract final class DesyncString {
  static const maxParts = 8;

  /// The first problem in [text], or null if the engine accepts it. Blank is
  /// accepted (no custom split).
  static DesyncStringError? validate(String text) {
    var parts = 0;
    var oobPending = false;
    for (final token in text.split(RegExp(r'[ \t]+')).where((t) => t.isNotEmpty)) {
      final match = _part.firstMatch(token);
      if (match == null) {
        final kind = token.length >= 2 && token[0] == '-' ? token[1] : '';
        final reason = switch (kind) {
          'r' => DesyncStringErrorReason.recordSplit,
          's' || 'o' || 'd' => DesyncStringErrorReason.position,
          _ => DesyncStringErrorReason.unknown,
        };
        return DesyncStringError(reason, token);
      }
      if (int.parse(match.group(3)!) > 1500) {
        return DesyncStringError(DesyncStringErrorReason.position, token);
      }
      if (++parts > maxParts) {
        return DesyncStringError(DesyncStringErrorReason.tooMany, token);
      }
      switch (match.group(1)) {
        case 'o':
          oobPending = true;
        case 'd':
          oobPending = false;
      }
    }
    return oobPending ? const DesyncStringError(DesyncStringErrorReason.oobWithoutTtl, '-o') : null;
  }

  /// [text] with single spaces, as stored and sent to the engine.
  static String normalize(String text) => text.trim().split(RegExp(r'[ \t]+')).where((t) => t.isNotEmpty).join(' ');

  static final _part = RegExp(r'^-([sod])(-?)(\d{1,4})(\+[sh])?$');
}

enum DesyncStringErrorReason {
  /// Not `-s`, `-o` or `-d`.
  unknown,

  /// `-r`: a TLS record split, which the server refuses.
  recordSplit,

  /// Missing or out of -1500..1500, or a suffix other than `+s`/`+h`.
  position,

  /// More than [DesyncString.maxParts] parts.
  tooMany,

  /// An `-o` with no `-d` after it stalls the server.
  oobWithoutTtl,
}

final class DesyncStringError {
  final DesyncStringErrorReason reason;

  /// The part at fault.
  final String token;

  const DesyncStringError(this.reason, this.token);

  @override
  String toString() => 'DesyncStringError($reason, $token)';
}
