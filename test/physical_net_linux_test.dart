import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/utils/physical_net.dart';

/// A stand-in for cattunnel-helper's diagnostics connections (HELPER.md).
void main() {
  late Directory dir;
  late ServerSocket helper;
  final requests = <Map<String, Object?>>[];

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    dir = await Directory.systemTemp.createTemp('ct_physnet');
    final path = '${dir.path}/helper.sock';
    helper = await ServerSocket.bind(InternetAddress(path, type: InternetAddressType.unix), 0);
    PhysicalNet.helperSocketOverride = path;
    requests.clear();
    helper.listen((client) {
      var buffer = <int>[];
      var piping = false;
      client.listen((data) {
        if (piping) {
          client.add(data); // relay: echo "the server"
          return;
        }
        buffer += data;
        final newline = buffer.indexOf(10);
        if (newline < 0) return;
        final request = jsonDecode(utf8.decode(buffer.sublist(0, newline))) as Map<String, Object?>;
        requests.add(request);
        final rest = buffer.sublist(newline + 1);
        if (request['cmd'] == 'probe') {
          client.write('${jsonEncode({'outcome': request['port'] == 443 ? 'ok' : 'refused'})}\n');
          unawaited(client.close());
        } else {
          piping = true;
          if (rest.isNotEmpty) client.add(rest);
        }
      });
    });
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    PhysicalNet.helperSocketOverride = null;
    await helper.close();
    await dir.delete(recursive: true);
  });

  test('probe goes to the helper', () async {
    expect(await PhysicalNet.probeTcp('192.0.2.1', 443, timeout: const Duration(seconds: 2)), 'ok');
    expect(await PhysicalNet.probeTcp('192.0.2.1', 444, timeout: const Duration(seconds: 2)), 'refused');
    expect(requests.first, {'cmd': 'probe', 'ip': '192.0.2.1', 'port': 443, 'timeout_ms': 2000});
  });

  test('relay: the socket carries only the server bytes', () async {
    final socket = await PhysicalNet.connect('192.0.2.1', 8443, timeout: const Duration(seconds: 2));
    socket.add(utf8.encode('ClientHello'));
    final echoed = await socket.first.timeout(const Duration(seconds: 2));
    socket.destroy();

    expect(utf8.decode(echoed), 'ClientHello');
    expect(requests.single, {'cmd': 'relay', 'ip': '192.0.2.1', 'port': 8443});
  });

  test('no helper: probe says so (null), connect falls back to a plain socket', () async {
    PhysicalNet.helperSocketOverride = '${dir.path}/missing.sock';
    expect(await PhysicalNet.probeTcp('192.0.2.1', 443, timeout: const Duration(seconds: 1)), isNull);
  });
}
