import 'dart:async';

import 'package:adguard_logger/adguard_logger.dart';
import 'package:flutter/services.dart';
import 'package:trusttunnel/common/logging/app_logger.dart';
import 'package:trusttunnel/data/model/server_data.dart';
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

    await repositories.vpnRepository.start(
      server: server.copyWith(serverData: data),
      routingProfile: routingProfile,
      excludedRoutes: await repositories.settingsRepository.getExcludedRoutes(),
      logLevel: logLevel,
    );

    return null;
  }
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
