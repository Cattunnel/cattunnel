import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app measures nothing by connecting to a server's address. Scans the
/// server list, the home screens, the subscriptions screen and the scopes for
/// any such call; the connection diagnostics (connection_diagnostics.dart,
/// network_check.dart) are a separate, user-started thing and are not in scope.
void main() {
  const roots = [
    'lib/feature/server/servers',
    'lib/feature/subscriptions',
    'lib/widgets',
    'lib/main.dart',
  ];
  // Nothing opens a socket on purpose: the ping comes from the engine
  // (VpnPlugin.tunnelPings), the SOCKS prober is gone (1.5.9.5).
  const allowed = <String>[];
  final forbidden = RegExp(r'probeTcp|Socket\.connect|SecureSocket|testServer\(|testAll\(|HomeLatencyRefresh');

  test('no TCP probe of a server from the server list, home screens or subscriptions', () {
    final hits = <String>[];
    for (final root in roots) {
      final entity = FileSystemEntity.typeSync(root) == FileSystemEntityType.directory
          ? Directory(root).listSync(recursive: true).whereType<File>()
          : [File(root)];
      for (final file in entity) {
        if (!file.path.endsWith('.dart') || allowed.contains(file.path)) continue;
        final lines = file.readAsLinesSync();
        for (final (index, line) in lines.indexed) {
          if (line.trimLeft().startsWith('//')) continue;
          if (forbidden.hasMatch(line)) hits.add('${file.path}:${index + 1}: ${line.trim()}');
        }
      }
    }
    expect(hits, isEmpty);
  });
}
