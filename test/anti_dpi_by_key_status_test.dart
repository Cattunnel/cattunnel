import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/routing_profile.dart';
import 'package:trusttunnel/data/model/routing_profile_data.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/vpn_configuration_log_level.dart';
import 'package:trusttunnel/data/model/vpn_log.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/data/repository/connection_notifications_settings_repository.dart';
import 'package:trusttunnel/data/repository/vpn_repository.dart';
import 'package:trusttunnel/di/model/dependency_factory.dart';
import 'package:trusttunnel/di/model/repository_factory.dart';
import 'package:trusttunnel/di/widgets/dependency_scope.dart';
import 'package:trusttunnel/feature/traffic/desktop_traffic_recorder.dart';
import 'package:trusttunnel/feature/vpn/domain/networks_memory.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';
import 'package:vpn_plugin/models/connect_failure.dart';
import 'package:vpn_plugin/models/net_diagnostic.dart';

class _FakeVpnRepository implements VpnRepository {
  final _states = StreamController<VpnState>.broadcast();

  @override
  Future<void> start({
    required Server server,
    required RoutingProfile routingProfile,
    required List<String> excludedRoutes,
    required VpnConfigurationLogLevel logLevel,
  }) async {
    _states.add(VpnState.connected);
  }

  @override
  Future<Stream<VpnState>> listenToStates() async => _states.stream;
  @override
  Future<void> updateConfiguration({
    required Server server,
    required RoutingProfile routingProfile,
    required List<String> excludedRoutes,
    required VpnConfigurationLogLevel logLevel,
  }) async {}
  @override
  Future<void> deleteConfiguration() async {}
  @override
  Future<Stream<VpnLog>> listenToLogs() async => const Stream<VpnLog>.empty();
  @override
  Stream<ConnectFailure> get connectFailures => const Stream<ConnectFailure>.empty();
  @override
  Stream<NetDiagnostic> get netDiagnostics => const Stream<NetDiagnostic>.empty();
  @override
  Future<VpnState> requestState() async => VpnState.disconnected;
  @override
  Future<void> stop() async {}
}

class _FakeDependencyFactory implements DependencyFactory {
  @override
  late SharedPreferences sharedPreferences;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeConnNotif extends ConnectionNotificationsSettingsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRepositoryFactory implements RepositoryFactory {
  final VpnRepository _vpn = _FakeVpnRepository();
  final _cn = _FakeConnNotif();
  @override
  VpnRepository get vpnRepository => _vpn;
  @override
  ConnectionNotificationsSettingsRepository get connectionNotificationsSettingsRepository => _cn;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<SharedPreferences> _connect(WidgetTester tester, ServerData data, {Map<String, Object> initial = const {}}) async {
  SharedPreferences.setMockInitialValues(initial);
  // Wi-Fi; on iOS (the variant) there is no platform fingerprint to wait for.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => ['wifi'],
  );
  final prefs = await SharedPreferences.getInstance();
  final depFactory = _FakeDependencyFactory()..sharedPreferences = prefs;
  final repoFactory = _FakeRepositoryFactory();
  final server = Server(id: 's1', serverData: data);

  await tester.pumpWidget(
    DependencyScope(
      dependenciesFactory: depFactory,
      repositoryFactory: repoFactory,
      child: VpnScope(
        appWindowController: null,
        vpnRepository: repoFactory.vpnRepository,
        child: MaterialApp(
          localizationsDelegates: Localization.localizationDelegates,
          supportedLocales: Localization.supportedLocales,
          home: Builder(
            builder: (context) => GestureDetector(
              onTap: () => VpnScope.vpnControllerOf(context).start(
                server: server,
                routingProfile: RoutingProfile(id: '', data: const RoutingProfileData.empty()),
                excludedRoutes: const [],
                logLevel: VpnConfigurationLogLevel.info,
              ),
              child: const Text('connect'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('connect'));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  return prefs;
}

/// Lets the timers of the round and of the status line run out.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 1));
  // The test host is Linux: the desktop traffic recorder started sampling
  // on "connected" and stops after one last real sample.
  DesktopTrafficRecorder.instance.onState(VpnState.disconnected, null);
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the key asks for the bypass: nothing under the button, the technique is remembered',
    (tester) async {
      final prefs = await _connect(
        tester,
        const ServerData.empty(name: 'srv', ipAddress: '1.2.3.4:443').copyWith(
          antiDpi: true,
          antiDpiMode: ServerData.antiDpiAuto,
        ),
      );

      expect(VpnScope.antiDpiStatus.value, isNull);
      // The hint for the key is kept (it goes first next time), but the
      // network is not marked: the subscription asked, not the network.
      expect(prefs.getKeys().where((key) => key.startsWith('anti_dpi_sub.s1.')).map(prefs.get), contains(1));
      expect(prefs.getKeys().where((key) => key.startsWith('anti_dpi_auto.s1.')), isEmpty);
      expect(NetworksMemory.all(prefs), isEmpty);
      await _finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'the key asks for the bypass: an old network mark of this key moves to the key (owner 02.11)',
    (tester) async {
      final prefs = await _connect(
        tester,
        const ServerData.empty(name: 'srv', ipAddress: '1.2.3.4:443').copyWith(
          antiDpi: true,
          antiDpiMode: ServerData.antiDpiAuto,
        ),
        initial: {'anti_dpi_auto.s1.oldnet': 2, 'anti_dpi_seen.s1.oldnet': 1, 'anti_dpi_auto.s2.oldnet': 3},
      );

      expect(prefs.getInt('anti_dpi_auto.s1.oldnet'), isNull);
      expect(prefs.getInt('anti_dpi_seen.s1.oldnet'), isNull);
      expect(prefs.getInt('anti_dpi_sub.s1.oldnet'), 2);
      // Another server without the bypass in its key keeps its mark.
      expect(prefs.getInt('anti_dpi_auto.s2.oldnet'), 3);
      expect(NetworksMemory.all(prefs).map((n) => n.key), ['oldnet']);
      await _finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'the key says nothing: the line says the plain connection worked',
    (tester) async {
      await _connect(tester, const ServerData.empty(name: 'srv', ipAddress: '1.2.3.4:443'));

      expect(VpnScope.antiDpiStatus.value?.step, AntiDpiStep.worked);
      expect(VpnScope.antiDpiStatus.value?.plainWorked, isTrue);
      await _finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
