import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Anti-DPI "auto" (ServerData.antiDpiAuto): VpnScope tries the DPI2
/// techniques 1, 2, 3 in turn, one round, [attemptTimeout] each, and this
/// remembers the one that connected - per server and per kind of network,
/// since the filters differ between the home Wi-Fi and the mobile operator.
/// The remembered one goes first next time.
class AntiDpiAuto {
  static const modes = [1, 2, 3];

  static const attemptTimeout = Duration(seconds: 6);

  /// Between stopping one technique and starting the next.
  static const switchPause = Duration(milliseconds: 1500);

  static const _keyPrefix = 'anti_dpi_auto';

  final SharedPreferences _preferences;

  const AntiDpiAuto(this._preferences);

  /// `wifi`, `mobile`, `ethernet` or `other` (unknown, or no network).
  static Future<String> networkKind() async {
    try {
      final kinds = await Connectivity().checkConnectivity();
      for (final (kind, name) in const [
        (ConnectivityResult.wifi, 'wifi'),
        (ConnectivityResult.mobile, 'mobile'),
        (ConnectivityResult.ethernet, 'ethernet'),
      ]) {
        if (kinds.contains(kind)) {
          return name;
        }
      }
    } on Object {
      // No connectivity backend (e.g. no NetworkManager on Linux).
    }

    return 'other';
  }

  List<int> order({required String serverId, required String network}) {
    final last = _preferences.getInt(_key(serverId, network));

    return [
      if (last != null && modes.contains(last)) last,
      ...modes.where((mode) => mode != last),
    ];
  }

  Future<void> remember({required String serverId, required String network, required int mode}) =>
      _preferences.setInt(_key(serverId, network), mode);

  String _key(String serverId, String network) => '$_keyPrefix.$serverId.$network';
}
