import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/feature/vpn/widgets/auto_failover_scope.dart';

Server _s(String id, String name, {String? sub = 'family', bool ruExit = false}) =>
    Server(id: id, serverData: ServerData.empty(name: name, subscriptionName: sub, ruExit: ruExit));

void main() {
  final servers = [
    _s('1', '🇩🇪 Германия 1'),
    _s('2', '🇩🇪 Германия 2'),
    _s('3', '🇳🇱 Нидерланды'),
    _s('4', '🇷🇺 Москва', ruExit: true),
    _s('5', '🇳🇱 Резерв Каскад'),
    _s('6', 'Мой ключ', sub: null),
    _s('7', 'US', sub: 'other'),
  ];

  test('next key of the same subscription, round', () {
    expect(AutoFailoverScope.nextServer(servers, servers[0])?.id, '2');
    expect(AutoFailoverScope.nextServer(servers, servers[1])?.id, '3');
    expect(AutoFailoverScope.nextServer(servers, servers[2])?.id, '1');
  });

  test('never a reserve, Russian-exit or other-subscription key', () {
    final seen = <String>{};
    var current = servers[0];
    for (var i = 0; i < 6; i++) {
      current = AutoFailoverScope.nextServer(servers, current)!;
      seen.add(current.id);
    }
    expect(seen, {'1', '2', '3'});
  });

  test('a self-added key or a lone subscription key has nowhere to go', () {
    expect(AutoFailoverScope.nextServer(servers, servers[5]), isNull);
    expect(AutoFailoverScope.nextServer(servers, servers[6]), isNull);
  });

  test('from a reserve key the person picked, the next regular one', () {
    expect(AutoFailoverScope.nextServer(servers, servers[4])?.id, '1');
  });
}
