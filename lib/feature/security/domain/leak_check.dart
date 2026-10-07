import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_latency_tester.dart';
import 'package:trusttunnel/feature/vpn/domain/server_tls.dart';

/// Where a request came from, as Cloudflare saw it (`/cdn-cgi/trace`).
class TraceInfo {
  final String ip;

  /// ISO country code, e.g. `DE`.
  final String? country;

  const TraceInfo({required this.ip, this.country});

  String get flag {
    final code = country;
    if (code == null || code.length != 2) {
      return '';
    }

    return String.fromCharCodes(code.toUpperCase().codeUnits.map((c) => c - 0x41 + 0x1F1E6));
  }
}

/// App-side part of the leak check.
///
/// CatTunnel itself is excluded from its own tunnel, so a plain request from
/// the app shows the *real* address. The exit address is therefore asked for
/// explicitly through the selected server: an authenticated CONNECT to
/// Cloudflare's 1.1.1.1:80 (same credential policy as diagnostics, see
/// [ServerTls]), then `GET /cdn-cgi/trace` over it - plain HTTP inside the
/// encrypted tunnel, answered with the IP/country the request left from.
abstract final class LeakCheck {
  static const _traceHost = '1.1.1.1';
  static const _timeout = Duration(seconds: 8);
  static const _authRejectedCodes = {403, 404, 405, 407};

  /// The real address (outside the tunnel).
  static Future<TraceInfo?> direct() async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(Uri.parse('https://$_traceHost/cdn-cgi/trace')).timeout(_timeout);
      final response = await request.close().timeout(_timeout);

      return _parse(await response.transform(utf8.decoder).join().timeout(_timeout));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// The address traffic leaves from through [server].
  static Future<TraceInfo?> throughServer(Server server, {required bool trustUserCas}) async {
    final securityContext = await ServerTls.contextFor(server, trustUserCas: trustUserCas);
    if (securityContext == null) {
      return null;
    }

    final (host, port) = ServerLatencyTester.parseAddress(server.serverData.ipAddress);
    Socket? socket;
    SecureSocket? secure;
    try {
      socket = await Socket.connect(host, port, timeout: _timeout);
      secure = await SecureSocket.secure(
        socket,
        host: ServerTls.sniOf(server),
        context: securityContext,
        supportedProtocols: const ['http/1.1'],
      ).timeout(_timeout);

      final data = <int>[];
      final reader = StreamIterator(secure);

      final credentials = base64.encode(utf8.encode('${server.serverData.username}:${server.serverData.password}'));
      secure.write(
        'CONNECT $_traceHost:80 HTTP/1.1\r\n'
        'Host: $_traceHost:80\r\n'
        'Proxy-Authorization: Basic $credentials\r\n'
        '\r\n',
      );
      await secure.flush();

      final headersEnd = await _readUntilHeadersEnd(reader, data);
      if (headersEnd < 0) {
        return null;
      }

      final status = int.tryParse(latin1.decode(data.sublist(0, headersEnd)).split(' ').elementAtOrNull(1) ?? '');
      if (status == null || _authRejectedCodes.contains(status) || status >= 300) {
        return null;
      }

      secure.write(
        'GET /cdn-cgi/trace HTTP/1.1\r\n'
        'Host: $_traceHost\r\n'
        'Connection: close\r\n'
        '\r\n',
      );
      await secure.flush();

      // Read until the trace is complete or the far end closes.
      try {
        while (await reader.moveNext().timeout(_timeout)) {
          data.addAll(reader.current);
          final body = latin1.decode(data.sublist(headersEnd));
          if (body.contains('\nloc=') && body.contains('\nip=') && body.contains('\nwarp=')) {
            break;
          }
        }
      } on TimeoutException {
        // Parse whatever arrived.
      }
      unawaited(reader.cancel());

      return _parse(latin1.decode(data.sublist(headersEnd)));
    } catch (_) {
      return null;
    } finally {
      secure?.destroy();
      socket?.destroy();
    }
  }

  /// Reads into [data] until the end of the first HTTP header block; the
  /// offset right after it, or -1.
  static Future<int> _readUntilHeadersEnd(StreamIterator<List<int>> reader, List<int> data) async {
    while (true) {
      for (var i = 3; i < data.length; i++) {
        if (data[i - 3] == 13 && data[i - 2] == 10 && data[i - 1] == 13 && data[i] == 10) {
          return i + 1;
        }
      }
      if (!await reader.moveNext().timeout(_timeout)) {
        return -1;
      }
      data.addAll(reader.current);
    }
  }

  static TraceInfo? _parse(String text) {
    String? value(String key) =>
        RegExp('^$key=(.+)\$', multiLine: true).firstMatch(text)?.group(1)?.trim();

    final ip = value('ip');

    return ip == null ? null : TraceInfo(ip: ip, country: value('loc'));
  }
}
