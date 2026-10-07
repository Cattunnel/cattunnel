import 'dart:convert';

import 'package:trusttunnel/data/model/certificate.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/vpn_protocol.dart';
import 'package:vpn_plugin/domain/configuration_codec.dart';
import 'package:vpn_plugin/models/configuration.dart';
import 'package:vpn_plugin/models/endpoint.dart';
import 'package:vpn_plugin/models/upstream_protocol.dart';

/// A new (unsaved) server from a decoded `tt://` link or config file.
ServerData serverDataFromEndpoint(Endpoint endpoint, {required String routingProfileId}) => ServerData.empty(
  name: endpoint.name,
  ipAddress: endpoint.addresses.first,
  domain: endpoint.hostName,
  username: endpoint.username,
  password: endpoint.password,
  // TODO: Create encoder
  // Konstantin Gorynin <k.gorynin@adguard.com>, 09 March 2026
  vpnProtocol: endpoint.upStreamProtocol == UpStreamProtocol.http2 ? VpnProtocol.http2 : VpnProtocol.quic,
  dnsServers: endpoint.dnsUpStreams,
  routingProfileId: routingProfileId,
  ipv6: endpoint.hasIpv6,
  antiDpi: endpoint.antiDpi,
  antiDpiMode: endpoint.antiDpiMode,
  tlsProfile: endpoint.tlsProfile,
  antiDpiDesync: endpoint.antiDpiDesync,
  h2PaddingFrames: endpoint.h2PaddingFrames,
  blockQuic: endpoint.blockQuic,
  ruExit: endpoint.ruExit,
  tlsPrefix: endpoint.clientRandom,
  certificate: endpoint.certificate.isEmpty
      ? null
      : Certificate(
          name: 'certificate.pem',
          data: endpoint.certificate,
        ),
  customSni: endpoint.customSni,
);

/// A new server from a trusttunnel_client config (TOML) - what the bot's
/// "Config for Linux / PC" button (tt2conf.py) sends. Only [endpoint] is
/// used: routing, lists and the rest come from the app's own settings.
///
/// Throws [FormatException] if [config] isn't such a config.
ServerData serverDataFromConfigFile(String config, {required String routingProfileId}) {
  final Configuration configuration;
  try {
    configuration = const ConfigurationCodec().decode(config);
  } on Object catch (e) {
    throw FormatException('Not a trusttunnel_client config: $e');
  }
  final endpoint = configuration.endpoint;
  if (endpoint.hostName.isEmpty ||
      endpoint.addresses.isEmpty ||
      endpoint.username.isEmpty ||
      endpoint.password.isEmpty) {
    throw const FormatException('The config has no [endpoint] with hostname, addresses, username and password');
  }
  final decoded = serverDataFromEndpoint(endpoint, routingProfileId: routingProfileId);
  // tt2conf.py writes TOML basic strings, escaped (`\"`, `\\`, `\uXXXX`);
  // the app's INI reader keeps them as they are.
  final server = decoded.copyWith(
    ipAddress: _unescape(decoded.ipAddress),
    domain: _unescape(decoded.domain),
    username: _unescape(decoded.username),
    password: _unescape(decoded.password),
    dnsServers: decoded.dnsServers.map(_unescape).toList(),
  );
  // The CLI config has no name key; tt2conf.py puts the name in the first
  // comment line ("# 🇩🇪 Германия 1"). The decoder's fallback is "Server".
  final commentName = _firstCommentLine(config);

  return commentName == null || endpoint.name != 'Server' ? server : server.copyWith(name: commentName);
}

/// TOML basic-string escapes are JSON's (plus rare `\U`/`\e`, left as they are).
String _unescape(String value) {
  if (!value.contains(r'\')) return value;
  try {
    return jsonDecode('"$value"') as String;
  } on FormatException {
    return value;
  }
}

String? _firstCommentLine(String config) {
  final first = config.trimLeft().split('\n').first.trim();
  if (!first.startsWith('#')) return null;
  final text = first.substring(1).trim();

  return text.isEmpty ? null : text;
}
