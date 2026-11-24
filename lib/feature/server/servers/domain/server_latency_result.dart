import 'package:flutter/foundation.dart';

/// The last in-tunnel measurement of a server: how long one request through
/// the tunnel took, and when it was made.
@immutable
class ServerLatencyResult {
  /// Round-trip time of the successful TCP connect, or `null` if the
  /// endpoint was unreachable within the test timeout.
  final Duration? latency;

  final DateTime testedAt;

  const ServerLatencyResult({
    required this.latency,
    required this.testedAt,
  });

  bool get reachable => latency != null;
}
