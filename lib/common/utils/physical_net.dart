import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Connections that must take the physical network even while the tunnel is
/// up: connection diagnostics and server latency tests.
///
/// Android needs nothing - the engine leaves the app itself out of the
/// tunnel. On Windows the CLI routes everything, so the plugin pins these
/// sockets to the physical adapter (IP_UNICAST_IF) through a small relay on
/// 127.0.0.1 (see physical_net.h). The kill switch still blocks them there.
/// On Linux the root helper does the same (SO_BINDTODEVICE); we talk to it
/// on its unix socket directly - no plugin in between (HELPER.md,
/// "Diagnostics over the physical interface").
///
/// While the tunnel is stuck, DNS goes only to the tunnel's resolver (the
/// CLI's firewall), so names are resolved up front ([prime], before the
/// tunnel starts) and remembered.
abstract final class PhysicalNet {
  static const _channel = MethodChannel('cattunnel/physical_net');

  static final _resolved = <String, InternetAddress>{};
  static Future<({int port, String token})?>? _relay;

  static bool get _windows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  static bool get _linux => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
  static bool get _pinned => _windows || _linux;

  /// The Linux helper's socket; tests point it elsewhere.
  @visibleForTesting
  static String? helperSocketOverride;

  static String get _helperSocket =>
      helperSocketOverride ?? Platform.environment['CATTUNNEL_HELPER_SOCKET'] ?? '/run/cattunnel/helper.sock';

  /// Resolves [hosts] now, while DNS still works, for later [connect]s.
  static Future<void> prime(Iterable<String> hosts) async {
    if (!_pinned) return;
    await Future.wait(hosts.map((host) => _address(host, refresh: true)));
  }

  /// A TCP connection to [host]:[port] over the physical network.
  static Future<Socket> connect(String host, int port, {required Duration timeout}) async {
    if (!_pinned) return Socket.connect(host, port, timeout: timeout);

    final address = await _address(host);
    if (_linux) {
      final helper = address == null ? null : await _helperConnection(timeout);
      if (helper == null) return Socket.connect(host, port, timeout: timeout);
      // The helper answers nothing on success: what follows is the server.
      helper.write('${jsonEncode({'cmd': 'relay', 'ip': address!.address, 'port': port})}\n');

      return helper;
    }

    final relay = await _relayInfo();
    if (relay == null || address == null) return Socket.connect(host, port, timeout: timeout);

    final socket = await Socket.connect(InternetAddress.loopbackIPv4, relay.port, timeout: timeout);
    socket.write('${relay.token} ${address.address} $port\n');

    return socket;
  }

  /// Windows and Linux: a TCP connect over the physical adapter - "ok",
  /// "timeout", "refused" or "failed". `null` elsewhere, or when the helper
  /// can't be reached (use a plain socket).
  static Future<String?> probeTcp(String host, int port, {required Duration timeout}) async {
    if (!_pinned) return null;
    final address = await _address(host);
    if (address == null) return 'failed';
    if (_linux) return _probeViaHelper(address, port, timeout);
    try {
      return await _channel.invokeMethod<String>('probeTcp', {
        'ip': address.address,
        'port': port,
        'timeoutMs': timeout.inMilliseconds,
      });
    } on Object {
      return null;
    }
  }

  /// Remembered addresses win (a lookup may hang on the tunnel's DNS and
  /// would count into a latency measurement); [prime] refreshes them.
  static Future<InternetAddress?> _address(String host, {bool refresh = false}) async {
    final literal = InternetAddress.tryParse(host);
    if (literal != null) return literal;
    final known = _resolved[host];
    if (known != null && !refresh) return known;
    try {
      final found = await InternetAddress.lookup(host).timeout(const Duration(seconds: 3));
      final address = found.firstWhere(
        (a) => a.type == InternetAddressType.IPv4,
        orElse: () => found.first,
      );
      _resolved[host] = address;

      return address;
    } on Object {
      return known;
    }
  }

  static Future<({int port, String token})?> _relayInfo() => _relay ??= () async {
    try {
      final info = await _channel.invokeMapMethod<String, Object>('relay');
      final port = info?['port'];
      final token = info?['token'];

      return port is int && token is String ? (port: port, token: token) : null;
    } on Object {
      return null;
    }
  }();

  /// Linux: a new connection to the helper, or `null` if there's none.
  static Future<Socket?> _helperConnection(Duration timeout) async {
    try {
      return await Socket.connect(
        InternetAddress(_helperSocket, type: InternetAddressType.unix),
        0,
        timeout: timeout,
      );
    } on Object {
      return null;
    }
  }

  static Future<String?> _probeViaHelper(InternetAddress address, int port, Duration timeout) async {
    final helper = await _helperConnection(timeout);
    if (helper == null) return null;
    try {
      helper.write(
        '${jsonEncode({'cmd': 'probe', 'ip': address.address, 'port': port, 'timeout_ms': timeout.inMilliseconds})}\n',
      );
      final line = await helper
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(timeout + const Duration(seconds: 2));
      final outcome = (jsonDecode(line) as Map<String, Object?>)['outcome'];

      return outcome is String ? outcome : 'failed';
    } on Object {
      return null;
    } finally {
      helper.destroy();
    }
  }
}
