import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/vpn_protocol.dart';
import 'package:trusttunnel/data/repository/server_repository.dart';
import 'package:trusttunnel/data/repository/subscription_repository.dart';
import 'package:trusttunnel/feature/vpn/domain/connection_diagnostics.dart';

/// Not reached on these paths: the verdict comes before the credentials.
class _UnusedServerRepository implements ServerRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _UnusedSubscriptionRepository implements SubscriptionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Server _server(String id, String address) => Server(
  id: id,
  serverData: ServerData(
    name: id,
    ipAddress: address,
    domain: 'vpn.example.org',
    username: 'u',
    password: 'p',
    vpnProtocol: VpnProtocol.http2,
    dnsServers: const [],
    routingProfileId: 'default',
    ipv6: false,
  ),
);

/// Runs the diagnosis with every outgoing TCP connect recorded.
Future<(ConnectionDiagnosis, List<String>)> _diagnose(
  Server server,
  List<Server> others, {
  required Future<Socket> Function(dynamic host, int port) connect,
}) async {
  final hosts = <String>[];
  final result = await IOOverrides.runZoned(
    () => ConnectionDiagnostics(
      subscriptionRepository: _UnusedSubscriptionRepository(),
      serverRepository: _UnusedServerRepository(),
    ).run(server, otherServers: others, onStep: (_, _) {}),
    socketConnect: (host, port, {sourceAddress, sourcePort = 0, timeout}) {
      hosts.add(host is InternetAddress ? host.address : '$host');

      return connect(host, port);
    },
  );

  return (result, hosts);
}

void main() {
  test('a refused server: only our own servers are asked, by TCP', () async {
    final server = _server('foreign-refused', '203.0.113.30:443');
    final others = [_server('other-a', '203.0.113.31:443'), _server('other-b', '203.0.113.32:8443')];

    final (result, hosts) = await _diagnose(
      server,
      others,
      connect: (_, _) async => throw const SocketException('refused', osError: OSError('Connection refused', 111)),
    );

    expect(result.verdict, DiagnosisVerdict.serverRefused);
    expect(hosts.toSet(), {'203.0.113.30', '203.0.113.31', '203.0.113.32'});
    // One connect per server: no second handshake to the same address.
    expect(hosts.where((h) => h == '203.0.113.30'), hasLength(1));
  });

  test('a handshake that dies: the verdict comes without our name going anywhere else', () async {
    // Accepts TCP and closes at once: TLS dies the way a filter's reset does.
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = listener.listen((socket) => socket.destroy());
    addTearDown(() async {
      await accepted.cancel();
      await listener.close();
    });
    final server = _server('foreign-tls', '127.0.0.1:${listener.port}');

    final (result, hosts) = await _diagnose(
      server,
      const [],
      // Outside the override's zone, or the connect would land back in it.
      connect: (host, port) => Zone.root.run(() => Socket.connect(host, port, timeout: const Duration(seconds: 2))),
    );

    expect(result.verdict, DiagnosisVerdict.tlsBlocked);
    expect(hosts.toSet(), {'127.0.0.1'});
  });
}
