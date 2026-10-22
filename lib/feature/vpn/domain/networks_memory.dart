import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/feature/vpn/domain/anti_dpi_auto.dart';
import 'package:trusttunnel/feature/vpn/domain/network_fingerprint.dart';

/// What the app remembers about one network.
///
/// The gateway and the DNS servers are not here on purpose: the screen of
/// the networks shows what the app knows, and the addresses of the network
/// are nobody else's business.
class RememberedNetwork {
  /// The key of the network: a hash, nothing else.
  final String key;

  /// The kind of the network: "wifi", "mobile", "ethernet" or "other".
  final String kind;

  /// The name the person gave it.
  final String? name;

  /// Until when the plain connection does not work here.
  final DateTime? directFailsUntil;

  /// The techniques that worked here, over the servers.
  final List<int> modes;

  const RememberedNetwork({
    required this.key,
    required this.kind,
    required this.name,
    required this.directFailsUntil,
    required this.modes,
  });

  /// Whether the app knows that the plain connection does not work here.
  bool get needsDpi => directFailsUntil != null;

  /// Whether the app knows anything about this network.
  bool get isKnown => needsDpi || modes.isNotEmpty;
}

/// The networks the app knows something about.
///
/// The memory is per server and per network: the key of a network is a hash
/// of its fingerprint (the gateway, the DNS servers, the search domains), so
/// the home Wi-Fi and the university are two networks and not one "wifi".
abstract final class NetworksMemory {
  /// Every network the app knows something about, the freshest first.
  static List<RememberedNetwork> all(SharedPreferences preferences, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final kinds = <String, String>{};
    final written = <String, int>{};
    final since = <String, int>{};
    final modes = <String, Set<int>>{};

    for (final key in preferences.getKeys()) {
      if (key.startsWith(NetworkFingerprint.kindKey(''))) {
        kinds[key.substring(NetworkFingerprint.kindKey('').length)] = preferences.getString(key) ?? 'other';
        continue;
      }
      if (key.startsWith(AntiDpiAuto.directSinceKeyPrefix)) {
        final network = _networkOf(key, AntiDpiAuto.directSinceKeyPrefix);
        final value = preferences.getInt(key);
        if (network == null || value == null) continue;
        since[network] = value;
        continue;
      }
      if (key.startsWith(AntiDpiAuto.directKeyPrefix)) {
        final network = _networkOf(key, AntiDpiAuto.directKeyPrefix);
        final value = preferences.getInt(key);
        if (network == null || value == null) continue;
        written[network] = value;
        continue;
      }
      if (key.startsWith(AntiDpiAuto.modeKeyPrefix)) {
        final network = _networkOf(key, AntiDpiAuto.modeKeyPrefix);
        final mode = preferences.getInt(key);
        if (network == null || mode == null) continue;
        (modes[network] ??= <int>{}).add(mode);
      }
    }

    // The memory of a network has a week of life, a day in the first
    // days on mobile (see [AntiDpiAuto.directTtl]).
    final direct = <String, DateTime>{};
    for (final entry in written.entries) {
      final network = entry.key;
      final kind = kinds[network] ?? 'other';
      final first = DateTime.fromMillisecondsSinceEpoch(since[network] ?? entry.value);
      final ttl = AntiDpiAuto.directTtl(kind: kind, since: first, now: at);
      final until = DateTime.fromMillisecondsSinceEpoch(entry.value).add(ttl);
      if (until.isAfter(at)) {
        direct[network] = until;
      }
    }

    final networks = <String, RememberedNetwork>{};
    for (final key in {...kinds.keys, ...direct.keys, ...modes.keys}) {
      final known = modes[key]?.toList();
      known?.sort();
      networks[key] = RememberedNetwork(
        key: key,
        kind: kinds[key] ?? 'other',
        name: NetworkFingerprint.customName(preferences, key),
        directFailsUntil: direct[key],
        modes: known ?? const [],
      );
    }

    final list = networks.values.where((network) => network.isKnown).toList();
    list.sort((a, b) {
      final untilA = a.directFailsUntil;
      final untilB = b.directFailsUntil;
      if (untilA != null && untilB != null) return untilA.compareTo(untilB);
      if (untilA != null) return -1;
      if (untilB != null) return 1;

      return a.key.compareTo(b.key);
    });

    return list;
  }

  /// Forgets one network: the label, the hint and the name.
  static Future<void> forget(SharedPreferences preferences, String key) async {
    for (final prefKey in preferences.getKeys().toList()) {
      if (_belongsTo(prefKey, key)) {
        await preferences.remove(prefKey);
      }
    }
  }

  /// Forgets every network.
  static Future<void> forgetAll(SharedPreferences preferences) async {
    for (final prefKey in preferences.getKeys().toList()) {
      if (_isNetworkKey(prefKey)) {
        await preferences.remove(prefKey);
      }
    }
  }

  /// Whether the key of the memory belongs to the network.
  static bool _belongsTo(String prefKey, String key) {
    if (prefKey == NetworkFingerprint.nameKey(key) || prefKey == NetworkFingerprint.kindKey(key)) return true;
    for (final prefix in [
      AntiDpiAuto.modeKeyPrefix,
      AntiDpiAuto.cursorKeyPrefix,
      AntiDpiAuto.directKeyPrefix,
      AntiDpiAuto.directSinceKeyPrefix,
    ]) {
      if (_networkOf(prefKey, prefix) == key) return true;
    }

    return false;
  }

  /// Whether the key of the memory is about a network at all.
  static bool _isNetworkKey(String prefKey) =>
      prefKey.startsWith(NetworkFingerprint.kindKey('')) ||
      prefKey.startsWith(NetworkFingerprint.nameKey('')) ||
      prefKey.startsWith(AntiDpiAuto.modeKeyPrefix) ||
      prefKey.startsWith(AntiDpiAuto.cursorKeyPrefix) ||
      prefKey.startsWith(AntiDpiAuto.directKeyPrefix) ||
      prefKey.startsWith(AntiDpiAuto.directSinceKeyPrefix);

  /// The network of a key of the memory: the last part of the key is the
  /// network, the rest is the server.
  static String? _networkOf(String key, String prefix) {
    if (!key.startsWith(prefix)) return null;
    final rest = key.substring(prefix.length);
    final parts = rest.split('.');
    if (parts.length < 2) return null;

    return parts.last;
  }
}
