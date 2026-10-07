import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:trusttunnel/common/error/exception_utils.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/logging/enum/logging_level.dart';
import 'package:trusttunnel/common/logging/enum/logging_security_type.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/vpn_configuration_log_level.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/feature/routing/routing/widgets/scope/routing_scope.dart';
import 'package:trusttunnel/feature/server/servers/domain/ru_exit_prompt.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/settings/app_logging/widgets/scope/app_logging_scope.dart';
import 'package:trusttunnel/feature/settings/excluded_routes/widgets/scope/excluded_routes_scope.dart';
import 'package:trusttunnel/feature/vpn/widgets/connection_error_dialog.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';

/// Connect/disconnect as the servers list does it (pre-connect subscription
/// refresh, log level, routing profile, error dialog) - shared by
/// [ServersCard] and the Cozy style's big connect button.
abstract final class ServerConnectionActions {
  static Future<void> disconnect(BuildContext context) {
    final controller = VpnScope.vpnControllerOf(context);

    return controller.stop();
  }

  /// Reconnects with the current settings when the VPN is up (or coming
  /// up): the Android engine reads routes, bypass lists and the app split
  /// only at start. Returns whether it reconnects.
  static bool reconnectIfActive(BuildContext context) {
    final state = VpnScope.vpnControllerOf(context, listen: false).state;
    final server = ServersScope.controllerOf(context, listen: false).selectedServer;
    if (state == VpnState.disconnected || server == null) {
      return false;
    }

    connect(context, server).ignore();

    return true;
  }

  /// Guards against a second tap while a connect is still being prepared
  /// (the pre-connect subscription refresh can take a few seconds, and the
  /// VPN state doesn't leave "disconnected" until it's done).
  static bool _connecting = false;

  static Future<void> connect(
    BuildContext context,
    Server server,
  ) async {
    if (_connecting) {
      return;
    }

    _connecting = true;
    try {
      await _prepareAndConnect(context, server);
    } finally {
      _connecting = false;
    }
  }

  static Future<void> _prepareAndConnect(
    BuildContext context,
    Server server,
  ) async {
    final serversController = ServersScope.controllerOf(context, listen: false);
    final controller = VpnScope.vpnControllerOf(context, listen: false);
    final excludedRoutes = ExcludedRoutesScope.controllerOf(context, listen: false).excludedRoutes;
    final loggingController = AppLoggingScope.controllerOf(context, listen: false);
    if (loggingController.loading) {
      return;
    }

    final logLevel = switch (loggingController.securityType) {
      LoggingSecurityType.stripped => VpnConfigurationLogLevel.error,
      LoggingSecurityType.full => switch (loggingController.loggingLevel) {
        LoggingLevel.defaultLevel => VpnConfigurationLogLevel.info,
        LoggingLevel.debug => VpnConfigurationLogLevel.debug,
      },
    };

    final routingProfile = RoutingScope.controllerOf(context, listen: false).routingList.firstWhere(
      (element) => element.id == server.serverData.routingProfileId,
    );

    final subscriptionName = server.serverData.subscriptionName;
    final serverToConnect = subscriptionName != null
        ? await _refreshSubscriptionIfDue(context, server, subscriptionName) ?? server
        : server;

    if (!context.mounted) {
      return;
    }

    // A self-added key that looks Russian: is it for trips abroad?
    final serverChecked = await RuExitPrompt.maybeAsk(context, serverToConnect);
    if (!context.mounted) {
      return;
    }

    serversController.pickServer(serverChecked.id);
    try {
      await controller.start(
        server: serverChecked,
        routingProfile: routingProfile,
        excludedRoutes: excludedRoutes,
        logLevel: logLevel,
      );
    } catch (exception) {
      if (!context.mounted) {
        return;
      }

      final message = ExceptionUtils.toPresentationException(exception: exception).toLocalizedString(context);
      await showDialog<void>(
        context: context,
        builder: (_) => ConnectionErrorDialog(message: message),
      );
    }
  }

  /// If [server] is managed by the subscription named [subscriptionName] and
  /// it hasn't been refreshed in the last 24h (or never), refreshes it before
  /// connecting so a rotated/revoked key takes effect immediately, and
  /// returns the possibly-updated [Server]. Best-effort: a refresh failure
  /// (no network, server down) never blocks connecting - falls back to the
  /// last-known-good server data by returning `null`.
  ///
  /// Kept short and backed off on failure: while this runs the VPN state is
  /// still "disconnected", so the button looks dead (and invites a second
  /// tap), and a failed refresh never updates `lastUpdatedAt` - without the
  /// backoff every tap would refetch, and each 404 counts toward the main
  /// host's fail2ban `nginx-sub` jail.
  static const _subscriptionRefreshCooldown = Duration(hours: 24);
  static const _preConnectRefreshTimeout = Duration(seconds: 4);
  static const _failedRefreshBackoff = Duration(hours: 1);
  static final _lastFailedRefresh = <String, DateTime>{};

  static Future<Server?> _refreshSubscriptionIfDue(
    BuildContext context,
    Server server,
    String subscriptionName,
  ) async {
    final subscriptionRepository = context.repositoryFactory.subscriptionRepository;
    final subscriptions = await subscriptionRepository.getAllSubscriptions();
    final subscription = subscriptions.firstWhereOrNull((s) => s.name == subscriptionName);
    if (subscription == null || !subscription.autoRefreshEnabled) {
      return null;
    }

    final lastUpdatedAt = subscription.lastUpdatedAt;
    final isDue = lastUpdatedAt == null || DateTime.now().difference(lastUpdatedAt) >= _subscriptionRefreshCooldown;
    if (!isDue) {
      return null;
    }

    final backoffKey = subscription.id ?? subscription.name;
    final failedAt = _lastFailedRefresh[backoffKey];
    if (failedAt != null && DateTime.now().difference(failedAt) < _failedRefreshBackoff) {
      return null;
    }

    try {
      // On timeout the fetch keeps going in the background and still lands
      // in the DB if it succeeds - we just don't hold the connection for it.
      await subscriptionRepository.refresh(subscription: subscription).timeout(_preConnectRefreshTimeout);
      _lastFailedRefresh.remove(backoffKey);
    } catch (_) {
      _lastFailedRefresh[backoffKey] = DateTime.now();

      return null;
    }

    if (!context.mounted) {
      return null;
    }

    return context.repositoryFactory.serverRepository.getServerById(id: server.id);
  }
}
