import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Anti-DPI "auto" (ServerData.antiDpiAuto): VpnScope tries the DPI2
/// techniques 1, 2, 3 in turn and this remembers two things about a
/// network: which technique worked there (a hint, it goes first next time)
/// and whether the plain connection works there at all (the network
/// remembers it for [memoryTtl]).
///
/// The memory is per server and per network - the key of the network is the
/// fingerprint (the gateway, the DNS servers, the search domains), not the
/// kind of it: the home Wi-Fi and the university are two networks, and
/// treating them as one was the reason the app started with a desync at
/// home.
class AntiDpiAuto {
  static const modes = [1, 2, 3];

  /// How many techniques one attempt tries.
  ///
  /// Three handshakes to the same name close to each other are what a
  /// filter's "freeze" keys on. The round rotates instead: the next
  /// attempt starts where this one stopped, so every technique gets its
  /// turn, two at a time.
  static const modesPerAttempt = 2;

  /// How long the app remembers that a network refused the plain
  /// connection.
  static const memoryTtl = Duration(days: 7);

  static const attemptTimeout = Duration(seconds: 6);

  /// Between stopping one technique and starting the next.
  static const switchPause = Duration(milliseconds: 1500);

  static const _keyPrefix = 'anti_dpi_auto';
  static const _cursorPrefix = 'anti_dpi_cursor';
  static const _directPrefix = 'anti_dpi_direct';

  /// Whether the round is going on right now.
  ///
  /// Nothing else may knock on the server's name while it does: the
  /// connection diagnostics and the auto would send handshakes to one SNI
  /// together, and a burst of them is what a filter's "freeze" keys on
  /// (three handshakes to the same name, close to each other).
  static final running = ValueNotifier<bool>(false);

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

  /// The techniques to try, in order: the one that worked in this network
  /// goes first, then the rest, starting where the last round stopped.
  /// At most [modesPerAttempt] of them.
  List<int> order({required String serverId, required String network}) {
    final hint = _preferences.getInt(_hintKey(serverId, network));
    final cursor = _preferences.getInt(_cursorKey(serverId, network)) ?? 0;
    final start = cursor.clamp(0, modes.length - 1);
    final rotated = <int>[...modes.skip(start), ...modes.take(start)];
    final withHint = hint != null && modes.contains(hint) ? [hint, ...rotated.where((m) => m != hint)] : rotated;

    return withHint.take(modesPerAttempt).toList();
  }

  /// The technique that worked in this network.
  Future<void> remember({required String serverId, required String network, required int mode}) async {
    await _preferences.setInt(_hintKey(serverId, network), mode);
    // The next round starts after the one that worked.
    final index = modes.indexOf(mode);
    await _preferences.setInt(_cursorKey(serverId, network), (index + 1) % modes.length);
  }

  /// Moves the round on after a failure, so the next attempt tries other
  /// techniques.
  Future<void> advance({required String serverId, required String network, required int count}) async {
    final cursor = _preferences.getInt(_cursorKey(serverId, network)) ?? 0;
    await _preferences.setInt(_cursorKey(serverId, network), (cursor + count) % modes.length);
  }

  /// Whether the plain connection does not work in this network: it failed
  /// there and the memory has not expired yet.
  bool directFails({required String serverId, required String network, DateTime? now}) {
    final at = _preferences.getInt(_directKey(serverId, network));
    if (at == null) return false;

    return (now ?? DateTime.now()).difference(DateTime.fromMillisecondsSinceEpoch(at)) < memoryTtl;
  }

  /// Remembers that the plain connection does not work in this network.
  Future<void> rememberDirectFailure({required String serverId, required String network}) =>
      _preferences.setInt(_directKey(serverId, network), DateTime.now().millisecondsSinceEpoch);

  /// The plain connection worked: the network is not a DPI one.
  Future<void> forgetDirectFailure({required String serverId, required String network}) =>
      _preferences.remove(_directKey(serverId, network));

  String _hintKey(String serverId, String network) => '$_keyPrefix.$serverId.$network';

  String _cursorKey(String serverId, String network) => '$_cursorPrefix.$serverId.$network';

  String _directKey(String serverId, String network) => '$_directPrefix.$serverId.$network';
}
