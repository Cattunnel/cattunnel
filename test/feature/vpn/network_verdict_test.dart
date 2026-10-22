import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/vpn_protocol.dart';
import 'package:trusttunnel/data/repository/server_repository.dart';
import 'package:trusttunnel/data/repository/subscription_repository.dart';
import 'package:trusttunnel/feature/vpn/domain/connection_diagnostics.dart';
import 'package:trusttunnel/feature/vpn/domain/net_diagnostics.dart';
import 'package:vpn_plugin/models/net_diagnostic.dart';

/// The repositories are not reached on the path we test here: the engine's
/// verdict answers the question before any probe goes out.
class _UnusedServerRepository implements ServerRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _UnusedSubscriptionRepository implements SubscriptionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  final server = Server(
    id: 'server-1',
    serverData: const ServerData(
      name: 'Test',
      ipAddress: '203.0.113.9:443',
      domain: 'vpn.example.org',
      username: 'u',
      password: 'p',
      vpnProtocol: VpnProtocol.http2,
      dnsServers: [],
      routingProfileId: 'default',
      ipv6: false,
    ),
  );

  test("the engine's verdict of a cut is the verdict of the network", () async {
    NetDiagnostics.record(
      server.id,
      NetDiagnostic.parse('symptom=cut_after_bytes proto=h2 up=1 down=2 dur_ms=10 idle_ms=5 repeat=2 cut=16342')!,
    );
    final steps = <DiagnosisStep, DiagnosisStepStatus>{};

    final result = await ConnectionDiagnostics(
      subscriptionRepository: _UnusedSubscriptionRepository(),
      serverRepository: _UnusedServerRepository(),
    ).run(server, otherServers: [], onStep: (step, status) => steps[step] = status);

    expect(result.verdict, DiagnosisVerdict.networkCuts);
    expect(result.engine?.symptom, NetDiagnostic.cutAfterBytes);
    // Nothing was probed: the engine had already seen it.
    expect(steps[DiagnosisStep.tls], DiagnosisStepStatus.skipped);
    expect(steps[DiagnosisStep.access], DiagnosisStepStatus.skipped);
  });

  test('an error from the server is not the network cutting the path', () {
    final error = NetDiagnostic.parse('symptom=server_error proto=h2 up=1 down=2 dur_ms=10 idle_ms=5 repeat=1 cut=0')!;

    expect(ConnectionDiagnostics.isCutVerdict(error), isFalse);
    expect(ConnectionDiagnostics.isCutVerdict(NetDiagnostic.parse('symptom=stall proto=h2 up=1 down=2')!), isTrue);
    expect(
      ConnectionDiagnostics.isCutVerdict(NetDiagnostic.parse('symptom=handshake_freeze proto=h2 up=0 down=0')!),
      isTrue,
    );
  });
}
