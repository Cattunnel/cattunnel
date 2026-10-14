import 'package:flutter/foundation.dart';
import 'package:trusttunnel/data/model/routing_profile.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/vpn_configuration_log_level.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';

mixin VpnController {
  /// The state as of the last rebuild of the widget tree.
  abstract final VpnState state;

  /// The state right now. While the app is in the background Flutter draws no
  /// frames, so [state] can be stale (the tile stopped the VPN meanwhile).
  VpnState get liveState;

  /// [liveState] as a listenable, for logic that must run in the background.
  ValueListenable<VpnState> get stateListenable;

  Future<void> start({
    required Server server,
    required RoutingProfile routingProfile,
    required List<String> excludedRoutes,
    required VpnConfigurationLogLevel logLevel,
  });

  Future<void> updateConfiguration({
    required Server server,
    required RoutingProfile routingProfile,
    required List<String> excludedRoutes,
    required VpnConfigurationLogLevel logLevel,
  });

  Future<void> deleteConfiguration();

  Future<void> stop();
}
