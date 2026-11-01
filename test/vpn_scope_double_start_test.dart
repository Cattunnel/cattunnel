import 'package:flutter/material.dart';
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
import 'package:trusttunnel/feature/vpn/models/vpn_controller.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';
import 'package:vpn_plugin/models/connect_failure.dart';
import 'package:vpn_plugin/models/net_diagnostic.dart';

class _CountingVpnRepository implements VpnRepository {
  int starts = 0;
  @override
  Future<void> start({required Server server, required RoutingProfile routingProfile, required List<String> excludedRoutes, required VpnConfigurationLogLevel logLevel}) async {
    starts++;
  }
  @override
  Future<Stream<VpnState>> listenToStates() async => const Stream<VpnState>.empty();
  @override
  Future<void> updateConfiguration({required Server server, required RoutingProfile routingProfile, required List<String> excludedRoutes, required VpnConfigurationLogLevel logLevel}) async {}
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
  Future<void> stop() async {
    // The engine's stop takes a moment: the second call of a switch arrives meanwhile.
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
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
  final _CountingVpnRepository _vpn = _CountingVpnRepository();
  final _cn = _FakeConnNotif();
  @override
  _CountingVpnRepository get vpnRepository => _vpn;
  @override
  ConnectionNotificationsSettingsRepository get connectionNotificationsSettingsRepository => _cn;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // S22 01.11: a server switch sent two starts 55-100 ms apart (the connect
  // button and VpnUpdateManager), the second one with the server object from
  // the servers list, and the VPN stayed in "connecting" for minutes.
  testWidgets('a server switch starts the engine once', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final depFactory = _FakeDependencyFactory()..sharedPreferences = prefs;
    final repoFactory = _FakeRepositoryFactory();

    const data = ServerData.empty(name: 'srv', ipAddress: '1.2.3.4:443');
    final fromButton = Server(id: 's1', serverData: data);
    // The same server as the list holds it: other data, same id.
    final fromList = Server(id: 's1', serverData: const ServerData.empty(name: 'srv (list)', ipAddress: '1.2.3.4:443'));
    final profile = RoutingProfile(id: '', data: const RoutingProfileData.empty());
    late VpnController controller;

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
              builder: (context) {
                controller = VpnScope.vpnControllerOf(context, listen: false);

                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );

    await tester.runAsync(() async {
      final first = controller.start(server: fromButton, routingProfile: profile, excludedRoutes: const [], logLevel: VpnConfigurationLogLevel.info);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final second = controller.start(server: fromList, routingProfile: profile, excludedRoutes: const [], logLevel: VpnConfigurationLogLevel.info);
      await Future.wait<void>([first, second]).timeout(const Duration(seconds: 20), onTimeout: () => <void>[]);
    });

    expect(repoFactory.vpnRepository.starts, 1);
  });
}
