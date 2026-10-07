import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:trusttunnel/common/controller/widget/state_consumer.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/logging/enum/logging_level.dart';
import 'package:trusttunnel/common/logging/enum/logging_security_type.dart';
import 'package:trusttunnel/data/model/vpn_configuration_log_level.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/feature/routing/routing/widgets/scope/routing_scope.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/settings/app_logging/widgets/scope/app_logging_scope.dart';
import 'package:trusttunnel/feature/settings/excluded_routes/widgets/scope/excluded_routes_scope.dart';
import 'package:trusttunnel/feature/settings/launch_and_connection/controller/auto_connect_on_launch_controller.dart';
import 'package:trusttunnel/feature/settings/launch_and_connection/controller/auto_connect_on_launch_state.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';

/// Restores the last VPN connection when automatic connection on launch is enabled.
///
/// Also connects when the app was opened from the Quick Settings tile
/// (Android, see CatTunnelActivity.kt), regardless of that setting.
class AutoConnectOnLaunchSettingsScope extends StatefulWidget {
  final Widget child;

  const AutoConnectOnLaunchSettingsScope({
    required this.child,
    super.key,
  });

  @override
  State<AutoConnectOnLaunchSettingsScope> createState() => _AutoConnectOnLaunchSettingsScopeState();
}

class _AutoConnectOnLaunchSettingsScopeState extends State<AutoConnectOnLaunchSettingsScope> {
  static const _tileLaunchChannel = MethodChannel('cattunnel/tile_launch');

  late final AutoConnectOnLaunchSettingsController _controller;
  Future<void>? _connectToLastServerFuture;

  /// Set when the app was opened from the Quick Settings tile; cleared once
  /// that connection attempt is handled.
  bool _pendingTileConnect = false;

  @override
  void initState() {
    super.initState();

    _controller = AutoConnectOnLaunchSettingsController(
      repository: context.repositoryFactory.autoConnectOnLaunchSettingsRepository,
    );

    _controller.fetch();

    _tileLaunchChannel.setMethodCallHandler((call) async {
      if (call.method == 'launchedFromTile') {
        _onTileLaunch();
      }
    });
    unawaited(_consumeColdStartTileLaunch());
  }

  Future<void> _consumeColdStartTileLaunch() async {
    try {
      final launchedFromTile = await _tileLaunchChannel.invokeMethod<bool>('consumeLaunchedFromTile');
      if (launchedFromTile ?? false) {
        _onTileLaunch();
      }
    } on MissingPluginException {
      // Not Android - there is no tile.
    }
  }

  void _onTileLaunch() {
    if (!mounted) {
      return;
    }

    _pendingTileConnect = true;
    _scheduleConnectToLastServerIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleConnectToLastServerIfNeeded();
  }

  @override
  Widget build(BuildContext context) => StateConsumer<AutoConnectOnLaunchSettingsController, AutoConnectOnLaunchState>(
    controller: _controller,
    listener: (_, _, _, _) => _scheduleConnectToLastServerIfNeeded(),
    builder: (_, _, child) => child!,
    child: widget.child,
  );

  /// Starts at most one connection attempt while dependencies update.
  void _scheduleConnectToLastServerIfNeeded() {
    if (_connectToLastServerFuture != null) {
      return;
    }

    final tilePendingAtStart = _pendingTileConnect;
    final future = _connectToLastServerIfNeeded();
    _connectToLastServerFuture = future;
    unawaited(
      future.whenComplete(() {
        _connectToLastServerFuture = null;

        // A tile launch that arrived while this attempt was in flight was
        // dropped by the guard above - give it its own pass now, instead of
        // leaving the flag armed for some unrelated later rebuild. Only when
        // it arrived *during* the attempt: a flag this attempt already saw
        // and left pending (data still loading) is picked up by the regular
        // listeners, and re-running here would spin.
        if (!tilePendingAtStart && _pendingTileConnect && mounted) {
          _scheduleConnectToLastServerIfNeeded();
        }
      }),
    );
  }

  /// Connects once to the saved server after settings and server data are ready.
  /// Invalid saved configuration is marked as handled without connecting.
  Future<void> _connectToLastServerIfNeeded() async {
    // Wait until settings are loaded and skip an already handled launch.
    final state = _controller.state;
    final fromTile = _pendingTileConnect;
    if (state.initial || state.loading || (state.connectOnLaunchHandled && !fromTile)) {
      return;
    }

    final loggingController = AppLoggingScope.controllerOf(context);
    if (loggingController.loading) {
      return;
    }

    // Wait for servers, or finish when auto-connect has no usable target.
    final serversController = ServersScope.controllerOf(context);
    if (!(state.enabled || fromTile) || state.lastServerId == null || serversController.servers.isEmpty) {
      if (!serversController.loading) {
        _markHandled();
      }

      return;
    }

    // Resolve the server saved by the previous successful selection.
    final server = serversController.servers.firstWhereOrNull(
      (server) => server.id == state.lastServerId,
    );
    if (server == null) {
      _markHandled();

      return;
    }

    // Resolve the routing profile required by the saved server.
    final routingProfile =
        RoutingScope.controllerOf(
          context,
          listen: false,
        ).routingList.firstWhereOrNull(
          (profile) => profile.id == server.serverData.routingProfileId,
        );
    if (routingProfile == null) {
      _markHandled();

      return;
    }

    // Read the remaining connection settings without subscribing to updates.
    final excludedRoutes = ExcludedRoutesScope.controllerOf(
      context,
      listen: false,
    ).excludedRoutes;
    final vpnController = VpnScope.vpnControllerOf(context, listen: false);

    // Mark the launch handled before handing the connection to the VPN controller.
    _markHandled();

    // The VPN outlives the app's UI: a new app process (Android killed the
    // old one) finds it up already. The tile only opens the app while
    // disconnected, but the VPN may have come up in between. Either way -
    // don't restart a working connection.
    if (vpnController.state != VpnState.disconnected) {
      return;
    }
    await vpnController.start(
      server: server,
      routingProfile: routingProfile,
      excludedRoutes: excludedRoutes,
      logLevel: switch (loggingController.securityType) {
        LoggingSecurityType.stripped => VpnConfigurationLogLevel.error,
        LoggingSecurityType.full => switch (loggingController.loggingLevel) {
          LoggingLevel.defaultLevel => VpnConfigurationLogLevel.info,
          LoggingLevel.debug => VpnConfigurationLogLevel.debug,
        },
      },
    );
  }

  void _markHandled() {
    _pendingTileConnect = false;
    _controller.markConnectOnLaunchHandled();
  }

  @override
  void dispose() {
    _tileLaunchChannel.setMethodCallHandler(null);
    _controller.dispose();
    super.dispose();
  }
}
