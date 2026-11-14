import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/feature/vpn/domain/anti_dpi_auto.dart';
import 'package:trusttunnel/feature/vpn/domain/connection_diagnostics.dart';
import 'package:trusttunnel/feature/vpn/domain/network_check.dart';

Server _server(String id, {bool subscription = true}) => Server(
  id: id,
  serverData: ServerData.empty(
    name: id,
    ipAddress: '203.0.113.5:8443',
    domain: 'vpn.example.org',
    subscriptionId: subscription ? '12' : null,
  ),
);

void main() {
  test('only subscription endpoints, deduplicated ports, pauses and existing diagnosis', () async {
    final targets = <String>[];
    final pauses = <Duration>[];
    final results = <NetworkCheckResult>[];
    var handshakes = 0;
    final check = NetworkCheck(
      lookup: (host) async {
        expect(host, 'vpn.example.org');
        return [InternetAddress('203.0.113.5')];
      },
      tcpProbe: (host, port) async {
        targets.add('$host:$port');
        return port == 8443;
      },
      diagnose: (server) async {
        handshakes++;
        expect(server.id, 'own');
        return const ConnectionDiagnosis(verdict: DiagnosisVerdict.inconclusive);
      },
      pause: (duration) async {
        pauses.add(duration);
      },
      isFrozen: (_) => false,
    );
    await check.run([_server('manual', subscription: false), _server('own')], onResult: results.add);
    expect(targets, ['203.0.113.5:8443', '203.0.113.5:443', '203.0.113.5:995']);
    expect(handshakes, 1);
    expect(pauses.every((d) => d >= const Duration(seconds: 1)), isTrue);
    expect(results.single.dnsMatches, isTrue);
    expect(results.single.tcp[443], isFalse);
  });
  test('frozen endpoints get no DNS/TCP/TLS probes', () async {
    final results = <NetworkCheckResult>[];
    final check = NetworkCheck(
      lookup: (_) => throw StateError('DNS'),
      tcpProbe: (_, _) => throw StateError('TCP'),
      diagnose: (_) => throw StateError('TLS'),
      isFrozen: (_) => true,
      pause: (_) async {},
    );
    await check.run([_server('frozen')], onResult: results.add);
    expect(results.single.frozen, isTrue);
  });
  test('cancel during DNS prevents all following probes', () async {
    final dns = Completer<List<InternetAddress>>();
    final check = NetworkCheck(
      lookup: (_) => dns.future,
      tcpProbe: (_, _) => throw StateError('TCP after cancel'),
      diagnose: (_) => throw StateError('TLS after cancel'),
      isFrozen: (_) => false,
      pause: (_) async {},
    );
    final running = check.run([_server('own')], onResult: (_) => fail('cancelled result'));
    check.cancel();
    dns.complete([InternetAddress('203.0.113.5')]);
    await running;
  });
  test('an active bypass round prevents any probes', () async {
    AntiDpiAuto.running.value = true;
    addTearDown(() => AntiDpiAuto.running.value = false);
    final check = NetworkCheck(lookup: (_) => throw StateError('DNS'), diagnose: (_) => throw StateError('TLS'));
    await check.run([_server('own')], onResult: (_) => fail('active round'));
  });
}
