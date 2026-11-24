import 'dart:io';

/// One rotation entry of a key (subscription tag 0x53, item 9a): an address
/// `host:port` and, after spaces, the SNI names of THAT server
/// (`host:port sni1 sni2`). There is no common name: each address brings
/// its own pool. Without names the engine uses the key's own name.
typedef RotationEntry = ({String address, List<String> sniPool});

/// Addresses for the timed rotation between servers of one key.
abstract final class RotationAddresses {
  /// The engine's `VPN_ROTATION_ADDRESSES_MAX`.
  static const maxCount = 16;

  /// The engine's `VPN_SNI_POOL_MAX`, per address.
  static const sniPoolMax = 8;

  /// The bounds of the random rotation term, the engine clamps to them too.
  static const minSecs = 60;
  static const maxSecs = 86400;

  static final _domain = RegExp(
    r'^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$',
    caseSensitive: false,
  );

  static int portOf(String primary) {
    final value = primary.trim();
    final colon = value.lastIndexOf(':');
    if (colon <= 0 || (value.contains(':') && value.startsWith('[') && value.indexOf(']') > colon)) return 443;
    final port = int.tryParse(value.substring(colon + 1));
    return port != null && port >= 1 && port <= 65535 ? port : 443;
  }

  /// `host[:port]` to `host:port` (IPv6 in brackets), or null when it is
  /// not an IPv4, `[IPv6]` or domain with a port from 1 to 65535.
  static String? normalize(String raw, int defaultPort) {
    final text = raw.trim();
    if (text.isEmpty || text.length > 255 || text.contains(RegExp(r'[\s/\\?#@]'))) return null;
    String host;
    String? explicitPort;
    if (text.startsWith('[')) {
      final end = text.indexOf(']');
      if (end < 0) return null;
      host = text.substring(1, end);
      final suffix = text.substring(end + 1);
      if (suffix.isNotEmpty) {
        if (!suffix.startsWith(':')) return null;
        explicitPort = suffix.substring(1);
      }
      final ip = InternetAddress.tryParse(host);
      if (ip?.type != InternetAddressType.IPv6) return null;
      host = '[${ip!.address}]';
    } else if (text.contains(':') && InternetAddress.tryParse(text)?.type == InternetAddressType.IPv6) {
      host = '[${InternetAddress.tryParse(text)!.address}]';
    } else if (text.contains(':')) {
      final index = text.lastIndexOf(':');
      if (text.indexOf(':') != index) return null;
      host = text.substring(0, index);
      explicitPort = text.substring(index + 1);
    } else {
      host = text;
    }
    final parsedPort = explicitPort == null ? defaultPort : int.tryParse(explicitPort);
    if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) return null;
    if (!host.startsWith('[')) {
      final ip = InternetAddress.tryParse(host);
      if (ip?.type == InternetAddressType.IPv4) {
        host = ip!.address;
      } else if (!_domain.hasMatch(host)) {
        return null;
      } else {
        host = host.toLowerCase();
      }
    }
    return '$host:$parsedPort';
  }

  /// A server name for the SNI of one address: a domain, lower case.
  static String? normalizeSni(String raw) {
    final name = raw.trim().toLowerCase();
    return _domain.hasMatch(name) ? name : null;
  }

  /// `host[:port] [sni ...]` split into its address and names, or null when
  /// the address or any name is wrong. Repeated names count once, at most
  /// [sniPoolMax] of them.
  static RotationEntry? parseEntry(String raw, int defaultPort) {
    final parts = raw.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    final address = normalize(parts.first, defaultPort);
    if (address == null) return null;
    final names = <String>[];
    for (final part in parts.skip(1)) {
      final name = normalizeSni(part);
      if (name == null) return null;
      if (!names.contains(name)) names.add(name);
    }
    if (names.length > sniPoolMax) return null;
    return (address: address, sniPool: names);
  }

  /// The entry back in the form of tag 0x53 and of the database.
  static String format(RotationEntry entry) => [entry.address, ...entry.sniPool].join(' ');

  static String? normalizeEntry(String raw, int defaultPort) {
    final entry = parseEntry(raw, defaultPort);
    return entry == null ? null : format(entry);
  }

  /// The valid entries in their order, one per address, at most [maxCount].
  /// The port of an address without one is the port of the key.
  static List<String> normalizeList(List<String> entries, List<String> primaryAddresses) =>
      entriesOf(entries, primaryAddresses).map(format).toList();

  static List<RotationEntry> entriesOf(List<String> entries, List<String> primaryAddresses) {
    final port = primaryAddresses.isEmpty ? 443 : portOf(primaryAddresses.first);
    final result = <RotationEntry>[];
    for (final raw in entries) {
      final entry = parseEntry(raw, port);
      if (entry == null || result.any((seen) => seen.address == entry.address)) continue;
      result.add(entry);
      if (result.length == maxCount) break;
    }
    return result;
  }

  /// A term bound from a link or the config: 0 is "not set" (the engine
  /// takes the session lifetime), anything else is clamped to the engine's range.
  static int clampSecs(int value) => value <= 0 ? 0 : value.clamp(minSecs, maxSecs);
}
