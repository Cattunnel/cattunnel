import 'package:flutter/foundation.dart';

/// Result of a single reachability test against a server's endpoint.
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
