import 'dart:async';
import 'dart:io';

import 'package:trusttunnel/common/utils/physical_net.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_latency_tester.dart';
import 'package:trusttunnel/feature/vpn/domain/anti_dpi_auto.dart';
import 'package:trusttunnel/feature/vpn/domain/connect_failures.dart';
import 'package:trusttunnel/feature/vpn/domain/connection_diagnostics.dart';

class NetworkCheckResult {
  final Server server;
  final List<String> resolvedAddresses;
  final bool? dnsMatches;
  final Map<int, bool> tcp;
  final ConnectionDiagnosis? diagnosis;
  final bool frozen;
  const NetworkCheckResult({
    required this.server,
    this.resolvedAddresses = const [],
    this.dnsMatches,
    this.tcp = const {},
    this.diagnosis,
    this.frozen = false,
  });
}

/// A bounded, explicit check of subscription endpoints. No foreign targets,
/// changes to the VPN, or inferred bypass-memory writes.
class NetworkCheck {
  static bool _running = false;
  bool _cancelled = false;
  final Future<List<InternetAddress>> Function(String) lookup;
  final Future<bool> Function(String, int) tcpProbe;
  final Future<ConnectionDiagnosis> Function(Server) diagnose;
  final Future<void> Function(Duration) pause;
  final bool Function(String) isFrozen;

  NetworkCheck({
    required this.diagnose,
    Future<List<InternetAddress>> Function(String)? lookup,
    Future<bool> Function(String, int)? tcpProbe,
    Future<void> Function(Duration)? pause,
    bool Function(String)? isFrozen,
  }) : lookup = lookup ?? InternetAddress.lookup,
       tcpProbe = tcpProbe ?? _tcp,
       pause = pause ?? Future<void>.delayed,
       isFrozen = isFrozen ?? ConnectFailures.isFrozen;

  void cancel() => _cancelled = true;

  static Future<bool> _tcp(String host, int port) async {
    const timeout = Duration(seconds: 3);
    try {
      final physical = await PhysicalNet.probeTcp(host, port, timeout: timeout);
      if (physical != null) return physical == 'ok';
      final socket = await PhysicalNet.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> run(List<Server> servers, {required void Function(NetworkCheckResult) onResult}) async {
    if (_running || AntiDpiAuto.running.value) return;
    _running = true;
    try {
      for (final server in servers) {
        if (_cancelled || AntiDpiAuto.running.value) return;
        if (server.serverData.subscriptionId == null && server.serverData.subscriptionName == null) continue;
        if (isFrozen(server.id)) {
          onResult(NetworkCheckResult(server: server, frozen: true));
          continue;
        }
        final (host, configuredPort) = ServerLatencyTester.parseAddress(server.serverData.ipAddress);
        final resolved = <InternetAddress>[];
        try {
          resolved.addAll(await lookup(server.serverData.domain).timeout(const Duration(seconds: 3)));
        } on Object {
          // A failed DNS lookup is reported as unknown, not as spoofing.
        }
        final literal = InternetAddress.tryParse(host);
        final matches = literal == null || resolved.isEmpty ? null : resolved.any((a) => a.address == literal.address);
        final tcp = <int, bool>{};
        for (final port in {configuredPort, 443, 8443, 995}) {
          if (_cancelled || AntiDpiAuto.running.value) return;
          if (isFrozen(server.id)) break;
          tcp[port] = await tcpProbe(host, port);
          await pause(const Duration(seconds: 1));
        }
        if (_cancelled || AntiDpiAuto.running.value) return;
        final frozen = isFrozen(server.id);
        // One existing diagnosis per endpoint: at most one TLS handshake.
        final diagnosis = frozen ? null : await diagnose(server);
        if (_cancelled) return;
        onResult(
          NetworkCheckResult(
            server: server,
            resolvedAddresses: resolved.map((a) => a.address).toList(),
            dnsMatches: matches,
            tcp: tcp,
            diagnosis: diagnosis,
            frozen: frozen,
          ),
        );
        await pause(const Duration(seconds: 1));
      }
    } finally {
      _running = false;
    }
  }
}
