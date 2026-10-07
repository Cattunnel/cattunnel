import 'dart:convert';
import 'dart:io';

import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/feature/security/domain/security_platform.dart';

/// TLS policy for app-side connections that carry the user's VPN
/// credentials (diagnostics' auth probe, the leak check) - the same trust the
/// VPN engine applies to the endpoint (see EndpointCaResolver):
///  - the server's own certificate (pinned / self-signed PEM) only, if set;
///  - otherwise the system roots minus the Russian Ministry ones;
///  - the stock trusted roots only when the user allowed user CAs.
abstract final class ServerTls {
  static String? _systemBundle;

  static String sniOf(Server server) {
    final customSni = server.serverData.customSni;

    return customSni != null && customSni.isNotEmpty ? customSni : server.serverData.domain;
  }

  /// `null` if no trustworthy context can be built (e.g. an unparsable
  /// pinned certificate) - callers must then not send credentials.
  static Future<SecurityContext?> contextFor(Server server, {required bool trustUserCas}) async {
    final own = server.serverData.certificate?.data;
    if (own != null && own.trim().isNotEmpty) {
      return _contextWith(own);
    }

    if (trustUserCas) {
      return SecurityContext(withTrustedRoots: true);
    }

    final bundle = _systemBundle ??= await SecurityPlatform.systemCaBundle();

    // No bundle (unreadable store, macOS) - fall back to the platform's own
    // roots.
    return bundle == null || bundle.isEmpty ? SecurityContext(withTrustedRoots: true) : _contextWith(bundle);
  }

  static SecurityContext? _contextWith(String pem) {
    try {
      return SecurityContext()..setTrustedCertificatesBytes(utf8.encode(pem));
    } catch (_) {
      return null;
    }
  }
}
