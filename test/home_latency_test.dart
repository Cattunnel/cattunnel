import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/data/repository/server_test_timeout_repository.dart';
import 'package:trusttunnel/feature/server/servers/controller/server_latency_controller.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_latency_result.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_latency_tester.dart';
import 'package:trusttunnel/feature/server/servers/widget/home_latency_refresh.dart';

class _Timeout implements ServerTestTimeoutRepository {
  @override
  Future<int> getValueSeconds() async => 5;
  @override
  Future<void> setValueSeconds(int seconds) async {}
}

class _Tester extends ServerLatencyTester {
  final pending = <Completer<ServerLatencyResult>>[];
  int calls = 0;
  @override
  Future<ServerLatencyResult> test(String address, {Duration timeout = const Duration(seconds: 5)}) {
    calls++;
    if (pending.isNotEmpty) return pending.removeAt(0).future;
    return Future.value(ServerLatencyResult(latency: const Duration(milliseconds: 42), testedAt: DateTime.now()));
  }
}

final _server = Server(
  id: '1',
  serverData: const ServerData.empty(name: 'test', ipAddress: '192.0.2.1:443'),
);

void main() {
  test('a measurement started before switching can never overwrite the new connection', () async {
    final tester = _Tester();
    final old = Completer<ServerLatencyResult>();
    final fresh = Completer<ServerLatencyResult>();
    tester.pending.addAll([old, fresh]);
    final controller = ServerLatencyController(timeoutRepository: _Timeout(), tester: tester);
    final before = controller.testServer(_server);
    await Future<void>.delayed(Duration.zero);
    controller.connectionChanged(VpnState.connecting);
    await controller.testServer(_server);
    expect(tester.calls, 1);
    controller.connectionChanged(VpnState.connected);
    final after = controller.testServer(_server);
    await Future<void>.delayed(Duration.zero);
    fresh.complete(ServerLatencyResult(latency: const Duration(milliseconds: 20), testedAt: DateTime.now()));
    await after;
    old.complete(ServerLatencyResult(latency: const Duration(milliseconds: 3000), testedAt: DateTime.now()));
    await before;
    expect(controller.resultFor('1')!.latency!.inMilliseconds, 20);
    controller.dispose();
  });
  test('disposing while a test is pending does not notify disposed listeners', () async {
    final tester = _Tester();
    final pending = Completer<ServerLatencyResult>();
    tester.pending.add(pending);
    final controller = ServerLatencyController(timeoutRepository: _Timeout(), tester: tester);
    final future = controller.testServer(_server);
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    pending.complete(ServerLatencyResult(latency: null, testedAt: DateTime.now()));
    await future;
  });
  testWidgets('connect refreshes; only one probe per minute, tab and background pause it', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final probe = _Tester();
    final controller = ServerLatencyController(timeoutRepository: _Timeout(), tester: probe);
    Future<void> mount(VpnState state, {bool visible = true}) => tester.pumpWidget(
      MaterialApp(
        home: TickerMode(
          enabled: visible,
          child: HomeLatencyRefresh(
            now: tester.binding.clock.now,
            controller: controller,
            server: _server,
            vpnState: state,
            child: const Scaffold(body: Text('home')),
          ),
        ),
      ),
    );
    await mount(VpnState.disconnected);
    await tester.pump(Duration.zero);
    expect(probe.calls, 1);
    controller.connectionChanged(VpnState.connecting);
    await mount(VpnState.connecting);
    await tester.pump(const Duration(seconds: 61));
    expect(probe.calls, 1);
    controller.connectionChanged(VpnState.connected);
    await mount(VpnState.connected);
    await tester.pump(Duration.zero);
    expect(probe.calls, 2);
    await tester.pump(const Duration(seconds: 59));
    expect(probe.calls, 2);
    await tester.pump(const Duration(seconds: 1));
    expect(probe.calls, 3);
    await mount(VpnState.connected, visible: false);
    await tester.pump(const Duration(minutes: 2));
    expect(probe.calls, 3);
    await mount(VpnState.connected);
    await tester.pump(Duration.zero);
    expect(probe.calls, 4);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 2));
    expect(probe.calls, 4);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(Duration.zero);
    expect(probe.calls, 5);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('a route covering the home pauses automatic probes', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final probe = _Tester();
    final controller = ServerLatencyController(timeoutRepository: _Timeout(), tester: probe);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: HomeLatencyRefresh(
          now: tester.binding.clock.now,
          controller: controller,
          server: _server,
          vpnState: VpnState.connected,
          child: const Scaffold(body: Text('home')),
        ),
      ),
    );
    await tester.pump(Duration.zero);
    expect(probe.calls, 1);
    unawaited(
      navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('other')))),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 2));
    expect(probe.calls, 1);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(probe.calls, 2);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
