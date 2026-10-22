import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/vpn_protocol.dart';
import 'package:trusttunnel/data/repository/server_repository.dart';
import 'package:trusttunnel/data/repository/subscription_repository.dart';
import 'package:trusttunnel/feature/vpn/domain/anti_dpi_auto.dart';
import 'package:trusttunnel/feature/vpn/domain/connection_diagnostics.dart';
import 'package:trusttunnel/feature/vpn/domain/network_fingerprint.dart';

class _UnusedServerRepository implements ServerRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _UnusedSubscriptionRepository implements SubscriptionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Server _server(String id, String ip) => Server(
  id: id,
  serverData: ServerData(
    name: 'Test',
    ipAddress: ip,
    domain: 'vpn.example.org',
    username: 'u',
    password: 'p',
    vpnProtocol: VpnProtocol.http2,
    dnsServers: const [],
    routingProfileId: 'default',
    ipv6: false,
  ),
);

Future<({String kind, String network})> _currentNetwork() async {
  final kind = await AntiDpiAuto.networkKind();

  return (kind: kind, network: (await NetworkFingerprints.current(kind: kind)).key);
}

void main() {
  test('a network known to cut the plain connection says "bypass", not "no internet"', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final server = _server('bypass-server', '203.0.113.10:443');
    final network = await _currentNetwork();
    await AntiDpiAuto(preferences).rememberDirectFailure(
      serverId: server.id,
      network: network.network,
    );
    final steps = <DiagnosisStep, DiagnosisStepStatus>{};

    final result = await ConnectionDiagnostics(
      subscriptionRepository: _UnusedSubscriptionRepository(),
      serverRepository: _UnusedServerRepository(),
      preferences: preferences,
    ).run(server, otherServers: [], onStep: (step, status) => steps[step] = status);

    expect(result.verdict, DiagnosisVerdict.bypassNeeded);
    expect(steps[DiagnosisStep.internet], DiagnosisStepStatus.skipped);
    expect(steps[DiagnosisStep.server], DiagnosisStepStatus.skipped);
  });

  test('the diagnosis waits for the round and repeats what it ended with', () async {
    final server = _server('auto-server', '203.0.113.11:443');
    final network = await _currentNetwork();
    AntiDpiAuto.running.value = false;
    AntiDpiAuto.lastRound.value = AntiDpiRound(
      serverId: server.id,
      network: network.network,
      kind: network.kind,
      triedPlain: true,
      triedModes: const [1, 2],
      workedMode: null,
      pathCut: true,
      at: DateTime.now(),
    );
    final steps = <DiagnosisStep, DiagnosisStepStatus>{};

    final result = await ConnectionDiagnostics(
      subscriptionRepository: _UnusedSubscriptionRepository(),
      serverRepository: _UnusedServerRepository(),
    ).run(server, otherServers: [], onStep: (step, status) => steps[step] = status);

    expect(result.verdict, DiagnosisVerdict.networkCuts);
    expect(result.auto?.triedModes, [1, 2]);
    expect(result.auto?.triedPlain, isTrue);
    expect(steps[DiagnosisStep.tls], DiagnosisStepStatus.skipped);
  });
}
