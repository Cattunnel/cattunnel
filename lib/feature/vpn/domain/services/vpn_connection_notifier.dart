import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:trusttunnel/common/localization/localization.dart';

/// Keeps CatTunnel down to a single VPN notification.
///
/// The vendor VPN service (closed TrustTunnel AAR) posts its own mandatory
/// foreground-service notification - hardcoded "TrustTunnel / VPN is running
/// in foreground", id [_vendorNotificationId] on channel [_vendorChannelId].
/// It can't be removed while the tunnel runs, but re-posting under the same
/// id from the same app replaces it in place, so "connected" goes there
/// instead of into a second notification. It disappears together with the
/// service on disconnect.
///
/// The "disconnected" notice is a separate, optional one (only when the user
/// has connection notifications enabled).
class VpnConnectionNotifier {
  static const _vendorChannelId = 'ConnectionStatus';
  static const _vendorChannelName = 'VPN connection status';
  static const _vendorNotificationId = 1;

  static const _channelId = 'vpn_status';
  static const _channelName = 'VPN status';
  static const _disconnectedNotificationId = 1000;

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  VpnConnectionNotifier({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Only Android is set up here (and only Android has the vendor
  /// foreground notification to replace).
  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(settings: const InitializationSettings(android: androidInit));
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Replaces the vendor foreground-service notification with a CatTunnel
  /// one, and clears a leftover "disconnected" notice if there is one.
  ///
  /// [disguised]: the launcher disguise is on - keep the notification
  /// neutral instead of "CatTunnel - connected to (server)".
  Future<void> notifyConnected({required String serverName, bool disguised = false}) async {
    if (!_isAndroid) {
      return;
    }
    await _ensureInitialized();
    await _plugin.cancel(id: _disconnectedNotificationId);

    const androidDetails = AndroidNotificationDetails(
      _vendorChannelId,
      _vendorChannelName,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
    );

    await _plugin.show(
      id: _vendorNotificationId,
      title: disguised ? Localization.ln.disguiseLabel : 'CatTunnel',
      body: disguised ? Localization.ln.disguiseNotificationBody : Localization.ln.notificationConnectedTo(serverName),
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
  }

  Future<void> notifyDisconnected({bool disguised = false}) async {
    if (!_isAndroid) {
      return;
    }
    await _ensureInitialized();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.low,
      priority: Priority.low,
    );

    await _plugin.show(
      id: _disconnectedNotificationId,
      title: disguised ? Localization.ln.disguiseLabel : 'CatTunnel',
      body: disguised ? Localization.ln.disguiseNotificationStopped : Localization.ln.notificationDisconnected,
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
  }
}
