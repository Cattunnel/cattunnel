import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/feature/vpn/domain/daily_bypass_preferences.dart';

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

  /// Upper bound; all network facts expire at local midnight.
  static const memoryTtl = Duration(days: 1);

  static const attemptTimeout = Duration(seconds: 6);

  /// Between stopping one technique and starting the next.
  static const switchPause = Duration(milliseconds: 1500);

  /// The keys of the memory. The key of a network is a hash, so these keys
  /// say nothing about the network itself.
  static const modeKeyPrefix = 'anti_dpi_auto';
  static const cursorKeyPrefix = 'anti_dpi_cursor';
  static const cursorSeenKeyPrefix = 'anti_dpi_cursor_seen';
  static String cursorSeenKey(String serverId, String network) => '$cursorSeenKeyPrefix.$serverId.$network';
  static const directKeyPrefix = 'anti_dpi_direct';

  /// When the plain connection first failed in this network: the mobile
  /// memory counts [mobileWarmup] from here.
  static const directSinceKeyPrefix = 'anti_dpi_direct_since';

  /// The technique that worked for a server whose subscription itself asks
  /// for the bypass. It still goes first next time, but it is not a fact
  /// about the network (the key asked for the bypass, not the network), so
  /// the list of the networks does not show it (owner 02.11).
  static const subHintKeyPrefix = 'anti_dpi_sub';

  /// When the technique last worked in the network, for the server
  /// (milliseconds since the epoch): the details of a network show it.
  static const seenKeyPrefix = 'anti_dpi_seen';

  /// The technique that worked in the network, for the server.
  static String modeKey(String serverId, String network) => '$modeKeyPrefix.$serverId.$network';

  /// Where the round starts the next time.
  static String cursorKey(String serverId, String network) => '$cursorKeyPrefix.$serverId.$network';

  /// The plain connection does not work in the network, for the server.
  static String directKey(String serverId, String network) => '$directKeyPrefix.$serverId.$network';

  /// When the plain connection first failed in the network, for the server.
  static String directSinceKey(String serverId, String network) => '$directSinceKeyPrefix.$serverId.$network';

  /// The technique that worked for a server with the bypass from the subscription.
  static String subHintKey(String serverId, String network) => '$subHintKeyPrefix.$serverId.$network';

  /// When the technique last worked in the network, for the server.
  static String seenKey(String serverId, String network) => '$seenKeyPrefix.$serverId.$network';

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
  ///
  /// [bySubscription]: the subscription asked for the bypass itself, the
  /// hint lives apart from the networks' memory (see [subHintKeyPrefix]).
  List<int> order({
    required String serverId,
    required String network,
    bool bySubscription = false,
    DateTime? now,
    int limit = modesPerAttempt,
  }) {
    final seen = _preferences.getInt(seenKey(serverId, network));
    final fresh =
        seen != null &&
        DailyBypassPreferences.sameDay(DateTime.fromMillisecondsSinceEpoch(seen), now ?? DateTime.now());
    final hint = bySubscription || fresh
        ? _preferences.getInt(
            bySubscription ? subHintKey(serverId, network) : _hintKey(serverId, network),
          )
        : null;
    final cursorAt = _preferences.getInt(cursorSeenKey(serverId, network));
    final cursorFresh =
        cursorAt != null &&
        DailyBypassPreferences.sameDay(DateTime.fromMillisecondsSinceEpoch(cursorAt), now ?? DateTime.now());
    final cursor = bySubscription || cursorFresh ? _preferences.getInt(_cursorKey(serverId, network)) ?? 0 : 0;
    final start = cursor.clamp(0, modes.length - 1);
    final rotated = <int>[...modes.skip(start), ...modes.take(start)];
    final withHint = hint != null && modes.contains(hint) ? [hint, ...rotated.where((m) => m != hint)] : rotated;

    return withHint.take(limit).toList();
  }

  /// The technique that worked in this network.
  ///
  /// With [bySubscription] the network is not marked: only the hint for the
  /// server is kept, and an old mark of this pair goes away.
  Future<void> remember({
    required String serverId,
    required String network,
    required int mode,
    bool bySubscription = false,
    DateTime? now,
  }) async {
    if (bySubscription) {
      await _preferences.setInt(subHintKey(serverId, network), mode);
      await _preferences.remove(_hintKey(serverId, network));
      await _preferences.remove(seenKey(serverId, network));
    } else {
      await _preferences.remove(failedKey(serverId, network));
      await _preferences.setInt(_hintKey(serverId, network), mode);
      await _preferences.setInt(seenKey(serverId, network), (now ?? DateTime.now()).millisecondsSinceEpoch);
    }
    // The next round starts after the one that worked.
    final index = modes.indexOf(mode);
    await _preferences.setInt(_cursorKey(serverId, network), (index + 1) % modes.length);
    await _preferences.setInt(cursorSeenKey(serverId, network), (now ?? DateTime.now()).millisecondsSinceEpoch);
  }

  /// Moves the round on after a failure, so the next attempt tries other
  /// techniques.
  Future<void> advance({required String serverId, required String network, required int count}) async {
    final cursor = _preferences.getInt(_cursorKey(serverId, network)) ?? 0;
    await _preferences.setInt(_cursorKey(serverId, network), (cursor + count) % modes.length);
    await _preferences.setInt(cursorSeenKey(serverId, network), DateTime.now().millisecondsSinceEpoch);
  }

  static Duration directTtl({required String kind, required DateTime since, required DateTime now}) =>
      DailyBypassPreferences.midnightAfter(since).difference(since);

  static const failedKeyPrefix = 'anti_dpi_failed';
  static String failedKey(String serverId, String network) => '$failedKeyPrefix.$serverId.$network';

  bool failedToday({required String serverId, required String network, DateTime? now}) {
    final at = _preferences.getInt(failedKey(serverId, network));
    return at != null && DailyBypassPreferences.sameDay(DateTime.fromMillisecondsSinceEpoch(at), now ?? DateTime.now());
  }

  Future<void> rememberFailed({required String serverId, required String network, DateTime? now}) async {
    await forgetDirectFailure(serverId: serverId, network: network);
    await _preferences.remove(modeKey(serverId, network));
    await _preferences.remove(seenKey(serverId, network));
    await _preferences.setInt(failedKey(serverId, network), (now ?? DateTime.now()).millisecondsSinceEpoch);
  }

  Future<void> migrateLegacyDirectMemory() async {
    const marker = 'dpi_daily_memory_migrated';
    if (_preferences.getBool(marker) == true) return;
    for (final key in _preferences.getKeys().toList()) {
      if (key.startsWith(directKeyPrefix)) await _preferences.remove(key);
    }
    await _preferences.setBool(marker, true);
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
    final written = DateTime.fromMillisecondsSinceEpoch(at);
    return !written.isAfter(when) && DailyBypassPreferences.sameDay(written, when);
  }

  /// Remembers that the plain connection does not work in this network.
  /// Call only after a technique succeeds in the same round.
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
      for (final prefix in [
        modeKeyPrefix,
        cursorKeyPrefix,
        cursorSeenKeyPrefix,
        directKeyPrefix,
        directSinceKeyPrefix,
        subHintKeyPrefix,
        seenKeyPrefix,
        failedKeyPrefix,
      ]) {
        if (key.startsWith('$prefix.$serverId.')) {
          await _preferences.remove(key);
        }
      }
    }
  }

  /// The subscription asks for the bypass for this server: what the round
  /// learnt about it before goes from the networks' memory to the server's
  /// own hints (older versions marked the network even then, although the
  /// subscription already turns the bypass on for that server).
  Future<void> moveToSubscription(String serverId) async {
    final prefix = '$modeKeyPrefix.$serverId.';
    for (final key in _preferences.getKeys().toList()) {
      if (!key.startsWith(prefix)) continue;
      final network = key.substring(prefix.length);
      final mode = _preferences.getInt(key);
      if (mode != null) await _preferences.setInt(subHintKey(serverId, network), mode);
      await _preferences.remove(key);
      await _preferences.remove(seenKey(serverId, network));
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
