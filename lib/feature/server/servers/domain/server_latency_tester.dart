import 'dart:io';

import 'package:trusttunnel/common/utils/physical_net.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_latency_result.dart';

/// {@template server_latency_tester}
/// Tests whether a server's endpoint is reachable by attempting a raw TCP
/// connect to it and timing how long the handshake takes.
///
/// This deliberately doesn't go through the VPN protocol itself (no auth,
/// no TLS) - it only answers "is something listening on this address right
/// now", the same question a user asking "is this server down" wants
/// answered quickly and without a real connection attempt.
/// {@endtemplate}
class ServerLatencyTester {
  const ServerLatencyTester();

  /// {@macro server_latency_tester}
  Future<ServerLatencyResult> test(
    String address, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final (host, port) = parseAddress(address);
    final stopwatch = Stopwatch()..start();

    try {
      // Windows: over the physical adapter, not through a running tunnel.
      final pinned = await PhysicalNet.probeTcp(host, port, timeout: timeout);
      if (pinned != null) {
        stopwatch.stop();

        return ServerLatencyResult(latency: pinned == 'ok' ? stopwatch.elapsed : null, testedAt: DateTime.now());
      }
      final socket = await Socket.connect(host, port, timeout: timeout);
      stopwatch.stop();
      socket.destroy();

      return ServerLatencyResult(latency: stopwatch.elapsed, testedAt: DateTime.now());
    } catch (_) {
      return ServerLatencyResult(latency: null, testedAt: DateTime.now());
    }
  }

  /// Splits a stored address into host/port, defaulting to port 443 when
  /// none is specified - matching how the app already treats addresses
  /// without an explicit port elsewhere (see the export/import link format).
  static (String, int) parseAddress(String address) {
    final trimmed = address.trim();

    // IPv6 literal with an explicit port: "[::1]:443".
    if (trimmed.startsWith('[')) {
      final closingBracket = trimmed.indexOf(']');
      if (closingBracket != -1) {
        final host = trimmed.substring(1, closingBracket);
        final rest = trimmed.substring(closingBracket + 1);
        final port = rest.startsWith(':') ? int.tryParse(rest.substring(1)) : null;

        return (host, port ?? 443);
      }
    }

    // Bare IPv6 literal has multiple colons and no explicit port here.
    if (trimmed.split(':').length > 2) {
      return (trimmed, 443);
    }

    final lastColon = trimmed.lastIndexOf(':');

    if (lastColon <= 0) {
      return (trimmed, 443);
    }

    final host = trimmed.substring(0, lastColon);
    final port = int.tryParse(trimmed.substring(lastColon + 1));

    return (host, port ?? 443);
  }
}
