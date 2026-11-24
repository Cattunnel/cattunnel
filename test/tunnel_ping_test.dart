import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/server_sort_option.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/feature/server/servers/controller/server_latency_controller.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_latency_result.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_sorting.dart';

class _Memory implements PingStore {
  Map<String, ServerLatencyResult> saved = {};

  @override
  Map<String, ServerLatencyResult> load() => saved;

  @override
  Future<void> save(Map<String, ServerLatencyResult> results) async => saved = {...results};
}

Server _server(String id, String name, {bool favorite = false}) => Server(
  id: id,
  favorite: favorite,
  serverData: ServerData.empty(name: name, ipAddress: '192.0.2.$id:443'),
);

// Item 13 of 1.5.9.5: the ping next to a key is the number the engine sends
// after it has picked the endpoint ({"cattunnel_ping_ms":N}); the app makes
// no request of its own.
void main() {
  late _Memory store;
  late ServerLatencyController controller;

  setUp(() {
    store = _Memory();
    controller = ServerLatencyController(store: store, now: () => DateTime(2026, 11, 20, 12));
  });

  tearDown(() => controller.dispose());

  test('the engine ping is stored for the connected server with its time', () async {
    controller.connectionChanged(VpnState.connecting, serverId: '1');
    controller.pingReported(87);
    await Future<void>.delayed(Duration.zero);

    final result = controller.resultFor('1')!;
    expect(result.latency, const Duration(milliseconds: 87));
    expect(result.testedAt, DateTime(2026, 11, 20, 12));
    expect(store.saved['1']!.latency, const Duration(milliseconds: 87));
  });

  test('a ping before "connecting" reaches the app belongs to the selected server', () {
    controller.connectionChanged(VpnState.disconnected, serverId: '2');
    controller.pingReported(40);

    expect(controller.resultFor('2')!.latency, const Duration(milliseconds: 40));
  });

  test('picking another server while connected does not move the value there', () {
    controller.connectionChanged(VpnState.connecting, serverId: '1');
    controller.connectionChanged(VpnState.connected, serverId: '1');
    controller.connectionChanged(VpnState.connected, serverId: '2');
    controller.pingReported(55);

    expect(controller.resultFor('1')!.latency, const Duration(milliseconds: 55));
    expect(controller.resultFor('2'), isNull);

    // A new attempt (reconnect for the other server) takes the new one.
    controller.connectionChanged(VpnState.disconnected, serverId: '2');
    controller.connectionChanged(VpnState.connecting, serverId: '2');
    controller.pingReported(66);
    expect(controller.resultFor('2')!.latency, const Duration(milliseconds: 66));
  });

  test('every new ping replaces the old value, listeners hear it', () {
    var heard = 0;
    controller.addListener(() => heard++);
    controller.connectionChanged(VpnState.connected, serverId: '1');
    controller.pingReported(100);
    controller.pingReported(30);

    expect(controller.resultFor('1')!.latency, const Duration(milliseconds: 30));
    expect(heard, 2);
  });

  test('no server known: nothing is stored', () {
    controller.pingReported(12);
    expect(controller.results, isEmpty);
  });

  test('values are read back from the store with their age', () {
    final at = DateTime(2026, 11, 20, 8);
    store.saved = {'1': ServerLatencyResult(latency: const Duration(milliseconds: 90), testedAt: at)};
    final fresh = ServerLatencyController(store: store);
    addTearDown(fresh.dispose);

    expect(fresh.resultFor('1')!.testedAt, at);
  });

  test('latency sort uses stored values: no value last, a favorite first even without one', () {
    final fast = ServerLatencyResult(latency: const Duration(milliseconds: 10), testedAt: DateTime(2026));
    final slow = ServerLatencyResult(latency: const Duration(milliseconds: 90), testedAt: DateTime(2026));
    store.saved = {'1': slow, '2': fast};
    final sorted = ServerLatencyController(store: store);
    addTearDown(sorted.dispose);

    final order = sortServers(
      [_server('1', 'slow'), _server('3', 'none'), _server('2', 'fast'), _server('4', 'fav', favorite: true)],
      ServerSortOption.latency,
      sorted,
    ).map((s) => s.serverData.name).toList();

    expect(order, ['fav', 'fast', 'slow', 'none']);
  });

  test('a ping from the engine reorders the latency sort', () {
    controller.connectionChanged(VpnState.connected, serverId: '3');
    controller.pingReported(5);

    final order = sortServers(
      [_server('1', 'a'), _server('3', 'pinged')],
      ServerSortOption.latency,
      controller,
    ).map((s) => s.serverData.name).toList();
    expect(order, ['pinged', 'a']);
  });
}
