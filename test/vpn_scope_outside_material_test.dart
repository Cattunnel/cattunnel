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
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';
import 'package:vpn_plugin/models/connect_failure.dart';
import 'package:vpn_plugin/models/net_diagnostic.dart';

class _FakeVpnRepository implements VpnRepository {
  @override
  Future<void> start({required Server server, required RoutingProfile routingProfile, required List<String> excludedRoutes, required VpnConfigurationLogLevel logLevel}) async {}
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('VpnScope outside MaterialApp: start does not crash on context.ln', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final depFactory = _FakeDependencyFactory()..sharedPreferences = prefs;
    final repoFactory = _FakeRepositoryFactory();

    final server = Server(
      id: 's1',
      serverData: const ServerData.empty(name: 'srv', ipAddress: '1.2.3.4:443'),
    );

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
                onTap: () async {
                  await VpnScope.vpnControllerOf(context).start(
                    server: server,
                    routingProfile: RoutingProfile(id: '', data: const RoutingProfileData.empty()),
                    excludedRoutes: const [],
                    logLevel: VpnConfigurationLogLevel.info,
                  );
                },
                child: const Text('connect'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('connect'));
    await tester.pumpAndSettle();
  });
}
