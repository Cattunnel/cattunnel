/// Why the engine couldn't reach the server (own engine build, PingFailure
/// in net/utils.h of tools/engine_native/0001-anti-dpi-desync.patch). Sent
/// right before the state change it explains; the official engine never
/// sends one.
enum ConnectFailure {
  /// No TCP connection (refused, unreachable, timed out), or QUIC failed.
  connect('connect'),

  /// TCP connected, the ClientHello went out, the connection was reset or
  /// closed: an SNI block, or the server refused it.
  helloReset('hello_reset'),

  /// TCP connected, the ClientHello went out, nothing came back in time:
  /// what a filter "freezing" the address looks like. Retrying with other
  /// tricks only extends the freeze.
  helloNoAnswer('hello_no_answer');

  final String value;

  const ConnectFailure(this.value);

  static ConnectFailure? fromValue(Object? value) => values.where((f) => f.value == value).firstOrNull;
}
