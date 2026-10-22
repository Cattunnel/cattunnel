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

  /// The same on a mobile network during the first [mobileWarmup]: the
  /// operator changes the gateway with the city, so a "yes, it is cut"
  /// here says less than a Wi-Fi one and is worth checking again every
  /// day. After the warmup the network behaves like Wi-Fi.
  static const mobileMemoryTtl = Duration(days: 1);
  static const mobileWarmup = Duration(days: 3);

  static const attemptTimeout = Duration(seconds: 6);

  /// Between stopping one technique and starting the next.
  static const switchPause = Duration(milliseconds: 1500);

  /// The keys of the memory. The key of a network is a hash, so these keys
  /// say nothing about the network itself.
  static const modeKeyPrefix = 'anti_dpi_auto';
  static const cursorKeyPrefix = 'anti_dpi_cursor';
  static const directKeyPrefix = 'anti_dpi_direct';

  /// When the plain connection first failed in this network: the mobile
  /// memory counts [mobileWarmup] from here.
  static const directSinceKeyPrefix = 'anti_dpi_direct_since';

  /// The technique that worked in the network, for the server.
  static String modeKey(String serverId, String network) => '$modeKeyPrefix.$serverId.$network';

  /// Where the round starts the next time.
  static String cursorKey(String serverId, String network) => '$cursorKeyPrefix.$serverId.$network';

  /// The plain connection does not work in the network, for the server.
  static String directKey(String serverId, String network) => '$directKeyPrefix.$serverId.$network';

  /// When the plain connection first failed in the network, for the server.
  static String directSinceKey(String serverId, String network) => '$directSinceKeyPrefix.$serverId.$network';

  /// The round that ended last, for the diagnostics dialog.
  static final lastRound = ValueNotifier<AntiDpiRound?>(null);

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

  /// How long the memory of a direct failure lives, from when it was first
  /// remembered in this network.
  static Duration directTtl({required String kind, required DateTime since, required DateTime now}) {
    if (kind == 'mobile' && now.difference(since) < mobileWarmup) return mobileMemoryTtl;

    return memoryTtl;
  }

  /// Whether the plain connection does not work in this network: it failed
  /// there and the memory has not expired yet.
  bool directFails({
    required String serverId,
    required String network,
    String kind = 'other',
    DateTime? now,
  }) {
    final at = _preferences.getInt(_directKey(serverId, network));
    if (at == null) return false;
    final when = now ?? DateTime.now();
    final since = DateTime.fromMillisecondsSinceEpoch(
      _preferences.getInt(_directSinceKey(serverId, network)) ?? at,
    );

    return when.difference(DateTime.fromMillisecondsSinceEpoch(at)) < directTtl(kind: kind, since: since, now: when);
  }

  /// Remembers that the plain connection does not work in this network.
  /// The first failure starts the mobile warmup; later ones only refresh
  /// the failure itself.
  Future<void> rememberDirectFailure({
    required String serverId,
    required String network,
    DateTime? now,
  }) async {
    final when = now ?? DateTime.now();
    if (!_preferences.containsKey(_directSinceKey(serverId, network))) {
      await _preferences.setInt(_directSinceKey(serverId, network), when.millisecondsSinceEpoch);
    }
    await _preferences.setInt(_directKey(serverId, network), when.millisecondsSinceEpoch);
  }

  /// The plain connection worked: the network is not a DPI one.
  Future<void> forgetDirectFailure({required String serverId, required String network}) async {
    await _preferences.remove(_directKey(serverId, network));
    await _preferences.remove(_directSinceKey(serverId, network));
  }

  /// Forgets everything the round remembered for the server, in every
  /// network: the subscription turned anti-DPI on for it, so what was
  /// learnt about it before says nothing now.
  Future<void> forgetServer(String serverId) async {
    for (final key in _preferences.getKeys().toList()) {
      for (final prefix in [modeKeyPrefix, cursorKeyPrefix, directKeyPrefix, directSinceKeyPrefix]) {
        if (key.startsWith('$prefix.$serverId.')) {
          await _preferences.remove(key);
        }
      }
    }
  }

  /// Waits for the round to end and returns what it ended with, if that
  /// was this server and not too long ago. There is no fixed "20 seconds":
  /// the round itself is bounded, and the diagnostics may only speak after
  /// it, or its handshakes would add to the burst.
  static Future<AntiDpiRound?> waitForRound({String? serverId}) async {
    final until = DateTime.now().add(roundWaitLimit);
    while (running.value && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final round = lastRound.value;
    if (round == null || (serverId != null && round.serverId != serverId)) return null;
    if (DateTime.now().difference(round.at) > roundFreshWindow) return null;

    return round;
  }

  /// A safety cap, above the longest round (three techniques, two pauses).
  static const roundWaitLimit = Duration(seconds: 45);
  static const roundFreshWindow = Duration(minutes: 2);

  String _hintKey(String serverId, String network) => modeKey(serverId, network);

  String _cursorKey(String serverId, String network) => cursorKey(serverId, network);

  String _directKey(String serverId, String network) => directKey(serverId, network);

  String _directSinceKey(String serverId, String network) => directSinceKey(serverId, network);
}

/// What one round of anti-DPI "auto" ended with: the technique that
/// worked, or that none did, and what it tried.
class AntiDpiRound {
  final String serverId;
  final String network;

  /// `wifi`, `mobile`, `ethernet` or `other`.
  final String kind;

  /// The plain connection was part of the round.
  final bool triedPlain;

  /// The techniques the round tried, in order.
  final List<int> triedModes;

  /// The technique that connected (0 for the plain connection), or null.
  final int? workedMode;

  /// At least one attempt was cut rather than unreachable: the path to the
  /// server is filtered, so this is a network problem, not a dead server.
  final bool pathCut;

  final DateTime at;

  const AntiDpiRound({
    required this.serverId,
    required this.network,
    required this.kind,
    required this.triedPlain,
    required this.triedModes,
    required this.workedMode,
    required this.pathCut,
    required this.at,
  });

  bool get failed => workedMode == null;
  bool get workedPlain => workedMode == 0;
}
