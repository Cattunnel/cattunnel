import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What tells one network from another: the gateway, the DNS servers and
/// the search domains.
///
/// No SSID: on Android it needs a permission (a question to the person
/// about their location), and on iOS an entitlement. The system gives all
/// three without any permission, and they change with the network: the
/// home Wi-Fi and the university have different gateways. The old key was
/// the kind of the network alone ("wifi"), and that is why the home and
/// the university were one network in the app's memory.
///
/// The fingerprint never leaves the phone. It is the key of what the app
/// remembers about a network; what goes into the report is the name of the
/// network, and the name is either what the person called it or a short
/// automatic one.
class NetworkFingerprint {
  /// The kind of the network: "wifi", "mobile", "ethernet" or "other".
  final String kind;

  /// The gateway of the default route, if the system tells it.
  final String gateway;

  /// The DNS servers of the network.
  final List<String> dnsServers;

  /// The search domains of the network ("home.arpa" and the like).
  final List<String> searchDomains;

  const NetworkFingerprint({
    required this.kind,
    required this.gateway,
    required this.dnsServers,
    required this.searchDomains,
  });

  /// A fingerprint with nothing in it: the platform has no such signal.
  static const empty = NetworkFingerprint(kind: 'other', gateway: '', dnsServers: [], searchDomains: []);

  /// Whether there is anything to tell the networks apart by.
  bool get isEmpty => gateway.isEmpty && dnsServers.isEmpty && searchDomains.isEmpty;

  /// The key of the network: the same network has the same key after a
  /// restart of the app, another network has another one.
  ///
  /// A short hash of the parts, so the key says nothing about the gateway
  /// and the DNS servers. The parts themselves stay on the phone.
  String get key {
    if (isEmpty) return kind;
    final parts = [kind, gateway, ...dnsServers, ...searchDomains]..sort((a, b) => a.compareTo(b));

    return _hash(parts.join('|'));
  }

  /// A short piece of the key, for the automatic name of a network. Empty
  /// when there was nothing to hash: the key is then the kind itself.
  String get shortId => isEmpty || key.length <= 4 ? '' : key.substring(0, 4);

  /// The name the person gave this network, if they did.
  static String? customName(SharedPreferences preferences, String key) {
    final name = preferences.getString(nameKey(key));

    return name == null || name.trim().isEmpty ? null : name.trim();
  }

  /// Remembers the name of the network (an empty name takes it away).
  static Future<void> rename(SharedPreferences preferences, String key, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      await preferences.remove(nameKey(key));

      return;
    }
    await preferences.setString(nameKey(key), trimmed);
  }

  /// The key of the kind of the network, so the list of the networks knows
  /// what each of them is.
  static String kindKey(String key) => 'network_kind.$key';

  /// The key of the name of the network.
  static String nameKey(String key) => 'network_name.$key';

  /// Remembers the kind of the network.
  static Future<void> rememberKind(SharedPreferences preferences, NetworkFingerprint fingerprint) async {
    if (preferences.getString(kindKey(fingerprint.key)) == fingerprint.kind) return;
    await preferences.setString(kindKey(fingerprint.key), fingerprint.kind);
  }

  /// A short, stable hash. Not a secret: the fingerprint stays on the
  /// phone, and the hash is only a key for it.
  static String _hash(String input) {
    var hash = 0xcbf29ce484222325;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }

    return hash.toRadixString(16).padLeft(16, '0');
  }
}

/// The fingerprint of the network the device is on right now.
///
/// Android gives it from the `LinkProperties` of the network (the gateway
/// of the default route, the DNS servers, the search domains), Windows from
/// the adapters (`GetAdaptersAddresses`), and Linux from `/proc/net/route`
/// and `/etc/resolv.conf`. Where the platform has nothing to say, the
/// fingerprint is empty and the kind of the network is the key.
abstract final class NetworkFingerprints {
  static const _appsChannel = MethodChannel('cattunnel/apps');
  static const _physicalNetChannel = MethodChannel('cattunnel/physical_net');

  /// The fingerprint of the current network.
  static Future<NetworkFingerprint> current({required String kind}) async {
    final parts = switch (defaultTargetPlatform) {
      TargetPlatform.android => await _android(),
      TargetPlatform.windows => await _windows(),
      TargetPlatform.linux => _linux(),
      _ => (gateway: '', dns: <String>[], domains: <String>[]),
    };

    return NetworkFingerprint(
      kind: kind,
      gateway: parts.gateway,
      dnsServers: parts.dns,
      searchDomains: parts.domains,
    );
  }

  static Future<({String gateway, List<String> dns, List<String> domains})> _android() async {
    try {
      final parts = await _appsChannel.invokeMapMethod<Object?, Object?>('networkFingerprint');
      final gateway = parts?['gateway'];
      final dns = parts?['dns'];
      final domains = parts?['domains'];

      return (
        gateway: gateway is String ? gateway : '',
        dns: dns is List ? dns.map((e) => '$e').toList() : const <String>[],
        domains: domains is List ? domains.map((e) => '$e').toList() : const <String>[],
      );
    } on Object {
      return (gateway: '', dns: const <String>[], domains: const <String>[]);
    }
  }

  static Future<({String gateway, List<String> dns, List<String> domains})> _windows() async {
    try {
      final parts = await _physicalNetChannel.invokeMapMethod<Object?, Object?>('fingerprint');
      final gateway = parts?['gateway'];
      final dns = parts?['dns'];

      return (
        gateway: gateway is String ? gateway : '',
        dns: dns is List ? dns.map((e) => '$e').toList() : const <String>[],
        domains: const <String>[],
      );
    } on Object {
      return (gateway: '', dns: const <String>[], domains: const <String>[]);
    }
  }

  /// The gateway of the default route and the DNS servers of the system.
  static ({String gateway, List<String> dns, List<String> domains}) _linux() {
    return (gateway: _linuxGateway(), dns: _linuxDns().dns, domains: _linuxDns().domains);
  }

  /// The gateway of the default route, from /proc/net/route. The address
  /// there is a little-endian hex number.
  static String _linuxGateway() {
    try {
      final file = File('/proc/net/route');
      if (!file.existsSync()) return '';

      return gatewayFromRoutes(file.readAsStringSync());
    } on Object {
      return '';
    }
  }

  /// The gateway of the default route out of the text of /proc/net/route.
  @visibleForTesting
  static String gatewayFromRoutes(String routes) {
    String? best;
    var bestMetric = 1 << 30;
    for (final line in const LineSplitter().convert(routes).skip(1)) {
      final fields = line.split(RegExp(r'\s+')).where((f) => f.isNotEmpty).toList();
      if (fields.length < 8) continue;
      if (fields[1] != '00000000' || fields[7] != '00000000') continue;
      final metric = int.tryParse(fields[6]) ?? bestMetric;
      if (metric < bestMetric) {
        bestMetric = metric;
        best = fields[2];
      }
    }
    if (best == null || best == '00000000') return '';

    return _hexToAddress(best);
  }

  /// The DNS servers and the search domains, from /etc/resolv.conf.
  static ({List<String> dns, List<String> domains}) _linuxDns() {
    var text = _linuxText('/etc/resolv.conf');
    // A system with systemd-resolved keeps a stub there, and the stub is
    // the same on every network: the real list is in the file next to it.
    if (text.contains('127.0.0.53')) {
      final real = _linuxText('/run/systemd/resolve/resolv.conf');
      if (real.isNotEmpty) {
        text = real;
      }
    }

    return dnsFromResolvConf(text);
  }

  /// The DNS servers and the search domains out of the text of a
  /// resolv.conf.
  @visibleForTesting
  static ({List<String> dns, List<String> domains}) dnsFromResolvConf(String text) {
    final dns = <String>[];
    final domains = <String>[];
    for (final line in const LineSplitter().convert(text)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final fields = trimmed.split(RegExp(r'\s+'));
      if (fields.length < 2) continue;
      if (fields[0] == 'nameserver') {
        dns.add(fields[1]);
      }
      if (fields[0] == 'search' || fields[0] == 'domain') {
        domains.addAll(fields.skip(1));
      }
    }

    return (dns: dns, domains: domains);
  }

  static String _linuxText(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return '';

      return file.readAsStringSync();
    } on Object {
      return '';
    }
  }

  /// A hex number of /proc/net/route as an address: the bytes come in the
  /// reverse order.
  static String _hexToAddress(String hex) {
    if (hex.length != 8) return '';
    final bytes = <int>[];
    for (var i = 0; i < 8; i += 2) {
      final value = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (value == null) return '';
      bytes.add(value);
    }

    return bytes.reversed.join('.');
  }
}
