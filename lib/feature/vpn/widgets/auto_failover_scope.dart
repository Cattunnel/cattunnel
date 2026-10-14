import 'dart:async';

import 'package:adguard_logger/adguard_logger.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/utils/physical_net.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/feature/routing/routing/widgets/scope/routing_scope.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_connection_actions.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/settings/app_logging/widgets/scope/app_logging_scope.dart';
import 'package:trusttunnel/feature/settings/excluded_routes/widgets/scope/excluded_routes_scope.dart';
import 'package:trusttunnel/feature/vpn/models/vpn_controller.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';

/// "Switch to another server if this one doesn't answer" - what the router
/// edition does (watcher, FAILOVER): the selected server hasn't connected
/// for [failAfter] while the device itself has internet - the next key of
/// the same subscription; after [backAfter] on it, one try to go back.
///
/// Only within one subscription (a self-added key is the person's own
/// choice), never to a reserve key ("Резерв"/"reserve" in the name - the
/// cascade is kept for emergencies) or a Russian-exit key.
abstract final class AutoFailoverPreferences {
  static const _key = 'auto_failover_enabled';

  static bool enabled(SharedPreferences preferences) => preferences.getBool(_key) ?? true;

  static Future<void> setEnabled(SharedPreferences preferences, bool value) => preferences.setBool(_key, value);
}

class AutoFailoverScope extends StatefulWidget {
  final Widget child;

  const AutoFailoverScope({required this.child, super.key});

  static const failAfter = Duration(minutes: 2);
  static const backAfter = Duration(minutes: 30);

  /// The next key after [current] among [servers] (in list order, round),
  /// or null if there's none to switch to.
  @visibleForTesting
  static Server? nextServer(List<Server> servers, Server current) {
    final subscription = current.serverData.subscriptionName;
    if (subscription == null) return null;
    final candidates = servers
        .where(
          (s) =>
              s.id == current.id ||
              (s.serverData.subscriptionName == subscription && !s.serverData.ruExit && !_isReserve(s)),
        )
        .toList();
    final index = candidates.indexWhere((s) => s.id == current.id);
    if (candidates.length < 2 || index < 0) return null;

    return candidates[(index + 1) % candidates.length];
  }

  static bool _isReserve(Server server) {
    final name = server.serverData.name.toLowerCase();

    return name.contains('резерв') || name.contains('reserve');
  }

  @override
  State<AutoFailoverScope> createState() => _AutoFailoverScopeState();
}

class _AutoFailoverScopeState extends State<AutoFailoverScope> {
  ValueListenable<VpnState>? _states;
  Timer? _failTimer;
  Timer? _backTimer;

  /// The server the person picked, while we're on another one.
  String? _preferredId;

  /// Our own stop+start is under way: its "disconnected" isn't the person's.
  bool _switching = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final states = VpnScope.vpnControllerOf(context, listen: false).stateListenable;
    if (!identical(states, _states)) {
      _states?.removeListener(_onState);
      _states = states..addListener(_onState);
    }
  }

  @override
  void dispose() {
    _states?.removeListener(_onState);
    _failTimer?.cancel();
    _backTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _onState() {
    final state = _states!.value;
    switch (state) {
      case VpnState.connected:
        _failTimer?.cancel();
        _failTimer = null;
        final current = _selected();
        if (_preferredId == null || current?.id == _preferredId) {
          _preferredId = null;
          _backTimer?.cancel();
          _backTimer = null;
        } else {
          _backTimer ??= Timer(AutoFailoverScope.backAfter, _goBack);
        }
      case VpnState.disconnected:
        if (_switching) return;
        // The person (or the app) stopped it: whatever we were doing is over.
        _failTimer?.cancel();
        _failTimer = null;
        _backTimer?.cancel();
        _backTimer = null;
        _preferredId = null;
      case VpnState.waitingForNetwork:
        // No network on the device: no server is to blame.
        _failTimer?.cancel();
        _failTimer = null;
      case VpnState.connecting || VpnState.recovering || VpnState.waitingForRecovery:
        _failTimer ??= Timer(AutoFailoverScope.failAfter, () => unawaited(_onFailed()));
    }
  }

  Server? _selected() => mounted ? ServersScope.controllerOf(context, listen: false).selectedServer : null;

  bool get _enabled => AutoFailoverPreferences.enabled(context.dependencyFactory.sharedPreferences);

  Future<void> _onFailed() async {
    _failTimer = null;
    if (!mounted || !_enabled) return;
    final state = _states!.value;
    if (state == VpnState.connected || state == VpnState.disconnected || state == VpnState.waitingForNetwork) {
      return;
    }
    final current = _selected();
    if (current == null) return;
    final next = AutoFailoverScope.nextServer(ServersScope.controllerOf(context, listen: false).servers, current);
    if (next == null) return;
    // The device's own internet first: without it every server looks dead.
    if (!await _hasInternet() || !mounted) {
      _onState(); // re-arm while still failing

      return;
    }
    _preferredId ??= current.id;
    _log('failover: ${current.serverData.name} did not connect for ${AutoFailoverScope.failAfter.inMinutes} min, '
        'switching to ${next.serverData.name}');
    await _switchTo(next);
  }

  Future<void> _goBack() async {
    _backTimer = null;
    final preferredId = _preferredId;
    if (!mounted || !_enabled || preferredId == null || _states!.value != VpnState.connected) return;
    final preferred = ServersScope.controllerOf(context, listen: false).servers.firstWhereOrNull(
      (s) => s.id == preferredId,
    );
    if (preferred == null) {
      _preferredId = null;

      return;
    }
    _log('failover: trying to go back to ${preferred.serverData.name}');
    await _switchTo(preferred);
  }

  Future<void> _switchTo(Server server) async {
    final routingProfile = RoutingScope.controllerOf(context, listen: false).routingList.firstWhereOrNull(
      (p) => p.id == server.serverData.routingProfileId,
    );
    final logging = AppLoggingScope.controllerOf(context, listen: false);
    if (routingProfile == null || logging.loading) return;
    final VpnController vpn = VpnScope.vpnControllerOf(context, listen: false);
    final excludedRoutes = ExcludedRoutesScope.controllerOf(context, listen: false).excludedRoutes;
    ServersScope.controllerOf(context, listen: false).pickServer(server.id);
    _switching = true;
    try {
      await vpn.start(
        server: server,
        routingProfile: routingProfile,
        excludedRoutes: excludedRoutes,
        logLevel: ServerConnectionActions.engineLogLevel(logging.securityType, logging.loggingLevel),
      );
    } on Object catch (error) {
      _log('failover: start failed (${error.runtimeType})');
    } finally {
      _switching = false;
    }
  }

  static Future<bool> _hasInternet() async {
    try {
      final socket = await PhysicalNet.connect('ya.ru', 443, timeout: const Duration(seconds: 5));
      socket.destroy();

      return true;
    } on Object {
      return false;
    }
  }

  static void _log(String message) => logger.logInfo(message, additionalTags: ['failover']);
}
