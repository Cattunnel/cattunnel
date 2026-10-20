/// What the engine saw in the last session to the endpoint (our engine build,
/// NetDiagnostics in core/src/net_diagnostics.cpp). The engine sends the
/// verdict as a key=value line: "symptom=cut_after_bytes proto=h2 up=8200
/// down=8100 dur_ms=1000 idle_ms=500 repeat=2 cut=16342".
class NetDiagnostic {
  /// The session to the endpoint never got established: the endpoint did not
  /// let us in.
  static const String handshakeFreeze = 'handshake_freeze';

  /// The session to the endpoint died after about the same number of bytes,
  /// several times in a row: the l4-25 rule of the TSPU.
  static const String cutAfterBytes = 'cut_after_bytes';

  /// The session was established, but the traffic stopped.
  static const String stall = 'stall';

  /// The endpoint closed the session with an error.
  static const String serverError = 'server_error';

  final String symptom;
  final String protocol;
  final int bytesUp;
  final int bytesDown;
  final int durationMs;
  final int idleMs;

  /// How many sessions in a row died the same way.
  final int repeat;

  /// The byte budget the sessions died at, if the symptom is a cut.
  final int cutBytes;

  const NetDiagnostic({
    required this.symptom,
    required this.protocol,
    required this.bytesUp,
    required this.bytesDown,
    required this.durationMs,
    required this.idleMs,
    required this.repeat,
    required this.cutBytes,
  });

  /// Parses the engine's line; null if it isn't one.
  static NetDiagnostic? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    final fields = <String, String>{};
    for (final token in raw.split(' ')) {
      final eq = token.indexOf('=');
      if (eq <= 0) continue;
      fields[token.substring(0, eq)] = token.substring(eq + 1);
    }

    final symptom = fields['symptom'];
    if (symptom == null || symptom.isEmpty) return null;

    int num(String? key) => int.tryParse(fields[key] ?? '') ?? 0;

    return NetDiagnostic(
      symptom: symptom,
      protocol: fields['proto'] ?? '',
      bytesUp: num('up'),
      bytesDown: num('down'),
      durationMs: num('dur_ms'),
      idleMs: num('idle_ms'),
      repeat: num('repeat'),
      cutBytes: num('cut'),
    );
  }

  /// Whether the session never got established.
  bool get isHandshakeFreeze => symptom == handshakeFreeze;

  /// Whether the symptom is a cut after a fixed number of bytes.
  bool get isCut => symptom == cutAfterBytes;

  /// Whether the symptom is a session that went silent.
  bool get isStall => symptom == stall;

  /// The bytes the session carried in total.
  int get totalBytes => bytesUp + bytesDown;
}
