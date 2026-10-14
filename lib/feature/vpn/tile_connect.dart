import 'dart:async';

import 'package:adguard_logger/adguard_logger.dart';
import 'package:flutter/services.dart';
import 'package:trusttunnel/common/logging/app_logger.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/di/model/initialization_helper.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_connection_actions.dart';
import 'package:trusttunnel/feature/vpn/domain/anti_dpi_auto.dart';

/// The Quick Settings tile's connect while the app isn't running (Android).
///
/// The vendor VPN service forgets its configuration on every stop, so after
/// a manual disconnect the tile has nothing to restart. Instead of keeping a
/// second copy of the configuration natively (it would go stale the moment
/// some code path updated only one of them), the tile starts a windowless
/// Flutter engine on [tileConnectMain] (see CatTunnelQsTileService /
/// TileConnector.kt), which builds the configuration exactly as a tap in the
/// app does - same repositories, same VpnRepository.start - for the last
/// server, and reports back.
///
/// What a tap in the app adds and the tile skips: the pre-connect
/// subscription refresh (the next app start does it), the "Russian key?"
/// question (asked when that server was first used) and the anti-DPI "auto"
/// round (the tile starts with the technique remembered for this server and
/// network; the engine keeps retrying with it).
abstract final class TileConnect {
  static const channel = MethodChannel('cattunnel/tile_connect');

  /// Starts the VPN to the last server; null when started, otherwise why not
  /// (no text from the configuration - it goes to the tile log).
  static Future<String?> run() async {
    final init = await const InitializationHelperIo(headless: true).init();
    final repositories = init.repositoryFactory;

    final lastServerId = await repositories.autoConnectOnLaunchSettingsRepository.getLastServerId();
    if (lastServerId == null) {
      return 'no last server';
    }
    final server = await repositories.serverRepository.getServerById(id: lastServerId);
    if (server == null) {
      return 'last server not found';
    }
    final routingProfile = await repositories.routingRepository.getProfileById(id: server.serverData.routingProfileId);
    if (routingProfile == null) {
      return 'routing profile not found';
    }

    final logging = repositories.loggingSettingsRepository;
    final logLevel = ServerConnectionActions.engineLogLevel(
      await logging.getSecurityType(),
      await logging.getLoggingLevel(),
    );

    var data = server.serverData;
    if (data.antiDpi && data.antiDpiMode == ServerData.antiDpiAuto) {
      final auto = AntiDpiAuto(init.dependenciesFactory.sharedPreferences);
      final order = auto.order(serverId: server.id, network: await AntiDpiAuto.networkKind());
      data = data.copyWith(antiDpiMode: order.first);
    }

    // Report only once the tunnel is up (or clearly isn't): the native side
    // destroys this engine on 'done', and destroyed right after the start
    // command the tunnel came up and dropped 2.5 s later (S22, 1.5.5 lab).
    final vpn = repositories.vpnRepository;
    final settled = Completer<String?>();
    var connecting = false;
    // A failed attempt isn't the end: the engine retries by itself. Keep the
    // last reason for the log in case it never connects.
    String? lastFailure;
    final states = (await vpn.listenToStates()).listen((state) {
      if (settled.isCompleted) return;
      switch (state) {
        case VpnState.connected:
          settled.complete(null);
        case VpnState.disconnected:
          if (connecting) settled.complete('disconnected while connecting (last failure: ${lastFailure ?? 'none'})');
        case VpnState.connecting || VpnState.recovering || VpnState.waitingForRecovery || VpnState.waitingForNetwork:
          connecting = true;
      }
    });
    final failures = vpn.connectFailures.listen((failure) => lastFailure = failure.value);
    try {
      await vpn.start(
        server: server.copyWith(serverData: data),
        routingProfile: routingProfile,
        excludedRoutes: await repositories.settingsRepository.getExcludedRoutes(),
        logLevel: logLevel,
      );

      // Still connecting by then: the engine keeps retrying alone; the native
      // timeout (45 s) is later than this.
      return await settled.future.timeout(_settleTimeout, onTimeout: () => null);
    } finally {
      await states.cancel();
      await failures.cancel();
    }
  }

  static const _settleTimeout = Duration(seconds: 35);
}

/// Entry point of the tile's background engine (called from main.dart's
/// `tileConnect`, which the native side runs by name).
Future<void> tileConnectMain() async {
  String? failure = 'not run';
  // The app reaches its logger through the zone, like main() sets it up.
  await runZoned(
    () async {
      try {
        failure = await TileConnect.run();
      } catch (error) {
        // The type only: a message could carry configuration text. A missing
        // plugin's message is just the method and channel name.
        failure = error is MissingPluginException ? 'MissingPluginException: ${error.message}' : error.runtimeType.toString();
      }
    },
    zoneValues: {Logger.loggerKey: AppLogger()},
  );
  await TileConnect.channel.invokeMethod<void>('done', {'connected': failure == null, 'why': failure ?? ''});
}
