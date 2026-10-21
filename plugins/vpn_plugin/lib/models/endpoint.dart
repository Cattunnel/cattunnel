import 'package:flutter/foundation.dart';
import 'package:vpn_plugin/models/upstream_protocol.dart';

/// {@template endpoint}
/// Connection settings for a remote VPN endpoint.
///
/// [Endpoint] defines how the client connects to the VPN server:
/// - possible server [addresses] and TLS [hostName],
/// - authentication ([username], [password]),
/// - certificate pinning and verification behavior,
/// - upstream protocol selection and optional fallback,
/// - optional traffic-handling features (e.g. anti-DPI).
///
/// This class is a data container. It does not validate that values are
/// syntactically correct (for example, that an address is a valid IP literal),
/// unless the backend enforces it later.
/// {@endtemplate}
@immutable
final class Endpoint {
  final String name;

  /// {@template endpoint_addresses}
  /// Candidate endpoint addresses to connect to.
  ///
  /// Each entry is typically an IP literal (IPv4 or IPv6) with an optional port.
  /// The backend (or encoder) may normalize entries without a port by applying
  /// a default port.
  ///
  /// An empty list usually means the backend will rely on other discovery or
  /// configuration mechanisms (if supported).
  /// {@endtemplate}
  final List<String> addresses;

  /// {@template endpoint_dns_upstreams}
  /// DNS upstream resolvers used when DNS interception/routing is enabled.
  ///
  /// The exact accepted formats depend on the backend. Common examples include:
  /// - `8.8.8.8:53` (plain DNS)
  /// - `tcp://8.8.8.8:53`
  /// - `tls://1.1.1.1`
  /// - `https://dns.example.com/dns-query`
  /// - DNS stamps (`sdns://...`)
  /// {@endtemplate}
  final List<String> dnsUpStreams;

  /// {@template endpoint_exclusions}
  /// Domains, IP addresses, or CIDR ranges that should be treated specially.
  ///
  /// The interpretation depends on the routing mode and backend rules. In many
  /// setups, exclusions define destinations that should be bypassed or tunneled
  /// depending on the selected [VpnMode] at the [Configuration] level.
  /// {@endtemplate}
  final List<String> exclusions;

  /// {@template endpoint_host_name}
  /// Host name used for TLS session establishment.
  ///
  /// This is typically used for SNI and certificate validation.
  /// {@endtemplate}
  final String hostName;

  /// {@template endpoint_username}
  /// Username used for endpoint authentication.
  /// {@endtemplate}
  final String username;

  /// {@template endpoint_password}
  /// Password used for endpoint authentication.
  /// {@endtemplate}
  final String password;

  /// {@template endpoint_client_random}
  /// TLS client random prefix represented as a hex string.
  ///
  /// This value is forwarded to the backend as-is. If the backend does not
  /// support this feature, it may be ignored.
  /// {@endtemplate}
  final String clientRandom;

  /// {@template endpoint_certificate}
  /// Endpoint certificate in PEM format.
  ///
  /// When provided, the backend may use it for certificate pinning or custom
  /// verification. When empty, the system trust store is typically used.
  /// {@endtemplate}
  final String certificate;

  /// {@template endpoint_upstream_protocol}
  /// Primary protocol used to communicate with the endpoint.
  /// {@endtemplate}
  final UpStreamProtocol upStreamProtocol;

  /// {@template endpoint_upstream_fallback_protocol}
  /// Optional fallback protocol used when [upStreamProtocol] fails.
  ///
  /// When `null`, the backend may treat this as "no fallback".
  /// {@endtemplate}
  final UpStreamProtocol? upStreamFallbackProtocol;

  /// {@template endpoint_anti_dpi}
  /// Whether anti-DPI measures should be enabled.
  ///
  /// The exact techniques and availability depend on the backend.
  /// {@endtemplate}
  final bool antiDpi;

  /// CatTunnel: with [antiDpi], the technique. 1..3 go to the engine as
  /// `anti_dpi_mode` (own engine build, DPI2); 4 = "auto" lives only in
  /// `tt://` links (tag 0x41) and the app, which resolves it to 1..3 before
  /// connecting; 0 - the engine's default split.
  final int antiDpiMode;

  /// CatTunnel: engine 1.3 `tls_profile` - chrome, firefox, safari or
  /// okhttp; empty - the engine default (chrome), and in `tt://` links (tag
  /// 0x42) "the app decides". The app resolves its "auto" before connecting.
  final String tlsProfile;

  /// Engine 1.3 `client_random_auth_key` (hex): TLS authorization by a key
  /// instead of the fixed [clientRandom] prefix. In `tt://` links - tag 0x0F
  /// (upstream). Empty - not used.
  final String clientRandomAuthKey;

  /// CatTunnel: a custom anti-DPI split (engine `anti_dpi_desync`, byedpi
  /// syntax, see DesyncString), overrides [antiDpiMode]; empty - none.
  final String antiDpiDesync;

  /// CatTunnel: engine `h2_padding_frames` (own build) - random padding on
  /// the first this many HTTP/2 frames; 0 - off.
  final int h2PaddingFrames;

  /// CatTunnel: engine `h2_padding_frames_min` (own build) - the lower bound
  /// of the number of the padded frames of a stream; the engine draws the
  /// number at random between this value and [h2PaddingFrames].
  final int h2PaddingFramesMin;

  /// CatTunnel: engine `h2_padding_per_stream` (own build) - count the padded
  /// frames per stream, not per session.
  final bool h2PaddingPerStream;

  /// CatTunnel: engine `h2_padding_min_bytes` (own build) - the lower bound
  /// of the junk of a frame, in bytes.
  final int h2PaddingMinBytes;

  /// CatTunnel: engine `h2_padding_max_bytes` (own build) - the upper bound
  /// of the junk of a frame, in bytes.
  final int h2PaddingMaxBytes;

  /// CatTunnel: engine `h2_padding_stream_bytes` (own build) - the junk
  /// budget of a stream, in bytes.
  final int h2PaddingStreamBytes;

  /// CatTunnel: engine `h2_padding_session_bytes` (own build) - the junk
  /// budget of a session, in bytes.
  final int h2PaddingSessionBytes;

  /// CatTunnel: engine `keepalive_interval_secs` (own build) - the base of
  /// the interval between the keepalive signals of an idle session, in
  /// seconds; 0 - off.
  final int keepaliveIntervalSecs;

  /// CatTunnel: engine `keepalive_signal` (own build) - the keepalive
  /// signal: `check` or `ping`; empty - the engine default (`check`).
  final String keepaliveSignal;

  /// CatTunnel: engine `session_lifetime_secs` (own build) - the lifetime of
  /// a session, in seconds; 0 - as long as the server keeps it.
  final int sessionLifetimeSecs;

  /// CatTunnel: engine `xhttp_enable` (own build) - carry the TCP
  /// connections of the apps in a pair of HTTP/2 streams instead of the
  /// CONNECT requests.
  final bool xhttpEnabled;

  /// CatTunnel: engine `xhttp_path` (own build) - the path prefix of the
  /// XHTTP requests; empty - the engine default (`/api/v2/`).
  final String xhttpPath;

  /// The engine's own default for `h2_padding_frames_min`.
  static const h2PaddingFramesMinDefault = 2;

  /// The engine's own default for `h2_padding_min_bytes`.
  static const h2PaddingMinBytesDefault = 1;

  /// The engine's own default for `h2_padding_max_bytes` (padding step 2).
  static const h2PaddingMaxBytesDefault = 64;

  /// The engine's own default for `h2_padding_stream_bytes`.
  static const h2PaddingStreamBytesDefault = 2048;

  /// The engine's own default for `h2_padding_session_bytes` (padding step 2).
  static const h2PaddingSessionBytesDefault = 4096;

  /// The engine's own default for `xhttp_path`.
  static const xhttpPathDefault = '/api/v2/';

  /// The keepalive signals the engine knows.
  static const keepaliveSignals = ['check', 'ping'];

  /// CatTunnel: engine `block_quic` (own build) - UDP to port 443 is refused,
  /// so browsers and apps fall back from QUIC to TCP inside the tunnel.
  final bool blockQuic;

  /// CatTunnel: a key with a Russian exit (for people abroad). App-side
  /// only - carried in `tt://` links (tag 0x40), never written to the
  /// engine config.
  final bool ruExit;

  /// {@template endpoint_has_ipv6}
  /// Whether IPv6 traffic may be routed through the endpoint.
  ///
  /// This is typically used by the backend to decide whether IPv6 connections
  /// can be accepted and tunneled.
  /// {@endtemplate}
  final bool hasIpv6;

  /// {@template endpoint_skip_verification}
  /// Whether endpoint TLS certificate verification should be skipped.
  ///
  /// When `true`, any certificate may be accepted. This is dangerous and should
  /// generally only be used for debugging or controlled environments.
  /// {@endtemplate}
  final bool skipVerification;

  final String customSni;

  /// {@macro endpoint}
  ///
  /// Defaults are intentionally permissive:
  /// - [addresses], [dnsUpStreams] and [exclusions] default to empty lists.
  /// - [clientRandom] and [certificate] default to empty strings.
  /// - [skipVerification] and [antiDpi] default to `false`.
  /// - [upStreamFallbackProtocol] defaults to `null` (no explicit fallback).
  ///
  /// The padding defaults are the ones the engine uses when the config says
  /// nothing about them (own build, padding step 2): two to four frames per
  /// stream, one to 64 bytes of junk per frame, 2 KB per stream and 4 KB per
  /// session.
  const Endpoint({
    this.addresses = const [],
    this.dnsUpStreams = const [],
    this.exclusions = const [],
    this.clientRandom = '',
    this.certificate = '',
    this.customSni = '',
    this.upStreamFallbackProtocol,
    this.antiDpi = false,
    this.antiDpiMode = 0,
    this.tlsProfile = '',
    this.clientRandomAuthKey = '',
    this.antiDpiDesync = '',
    this.h2PaddingFrames = 0,
    this.h2PaddingFramesMin = h2PaddingFramesMinDefault,
    this.h2PaddingPerStream = true,
    this.h2PaddingMinBytes = h2PaddingMinBytesDefault,
    this.h2PaddingMaxBytes = h2PaddingMaxBytesDefault,
    this.h2PaddingStreamBytes = h2PaddingStreamBytesDefault,
    this.h2PaddingSessionBytes = h2PaddingSessionBytesDefault,
    this.keepaliveIntervalSecs = 0,
    this.keepaliveSignal = '',
    this.sessionLifetimeSecs = 0,
    this.xhttpEnabled = false,
    this.xhttpPath = '',
    this.blockQuic = false,
    this.ruExit = false,
    this.skipVerification = false,
    required this.name,
    required this.hostName,
    required this.username,
    required this.password,
    required this.upStreamProtocol,
    required this.hasIpv6,
  });

  @override
  String toString() =>
      'Endpoint(name: $name, addresses: $addresses, dnsUpStreams: $dnsUpStreams, exclusions: $exclusions, hostName: $hostName, username: $username, password: $password, clientRandom: $clientRandom, certificate: $certificate, upStreamProtocol: $upStreamProtocol, upStreamFallbackProtocol: $upStreamFallbackProtocol, antiDpi: $antiDpi, antiDpiMode: $antiDpiMode, tlsProfile: $tlsProfile, clientRandomAuthKey: ${clientRandomAuthKey.isEmpty ? '' : '***'}, antiDpiDesync: $antiDpiDesync, h2PaddingFrames: $h2PaddingFrames, h2PaddingFramesMin: $h2PaddingFramesMin, h2PaddingPerStream: $h2PaddingPerStream, h2PaddingMinBytes: $h2PaddingMinBytes, h2PaddingMaxBytes: $h2PaddingMaxBytes, h2PaddingStreamBytes: $h2PaddingStreamBytes, h2PaddingSessionBytes: $h2PaddingSessionBytes, keepaliveIntervalSecs: $keepaliveIntervalSecs, keepaliveSignal: $keepaliveSignal, sessionLifetimeSecs: $sessionLifetimeSecs, xhttpEnabled: $xhttpEnabled, xhttpPath: $xhttpPath, blockQuic: $blockQuic, ruExit: $ruExit, hasIpv6: $hasIpv6, skipVerification: $skipVerification)';

  @override
  bool operator ==(covariant Endpoint other) {
    if (identical(this, other)) return true;

    return listEquals(other.addresses, addresses) &&
        listEquals(other.dnsUpStreams, dnsUpStreams) &&
        listEquals(other.exclusions, exclusions) &&
        other.name == name &&
        other.hostName == hostName &&
        other.username == username &&
        other.password == password &&
        other.clientRandom == clientRandom &&
        other.certificate == certificate &&
        other.upStreamProtocol == upStreamProtocol &&
        other.upStreamFallbackProtocol == upStreamFallbackProtocol &&
        other.antiDpi == antiDpi &&
        other.antiDpiMode == antiDpiMode &&
        other.tlsProfile == tlsProfile &&
        other.clientRandomAuthKey == clientRandomAuthKey &&
        other.antiDpiDesync == antiDpiDesync &&
        other.h2PaddingFrames == h2PaddingFrames &&
        other.h2PaddingFramesMin == h2PaddingFramesMin &&
        other.h2PaddingPerStream == h2PaddingPerStream &&
        other.h2PaddingMinBytes == h2PaddingMinBytes &&
        other.h2PaddingMaxBytes == h2PaddingMaxBytes &&
        other.h2PaddingStreamBytes == h2PaddingStreamBytes &&
        other.h2PaddingSessionBytes == h2PaddingSessionBytes &&
        other.keepaliveIntervalSecs == keepaliveIntervalSecs &&
        other.keepaliveSignal == keepaliveSignal &&
        other.sessionLifetimeSecs == sessionLifetimeSecs &&
        other.xhttpEnabled == xhttpEnabled &&
        other.xhttpPath == xhttpPath &&
        other.blockQuic == blockQuic &&
        other.ruExit == ruExit &&
        other.hasIpv6 == hasIpv6 &&
        other.skipVerification == skipVerification;
  }

  @override
  int get hashCode => Object.hashAll([
    name,
    addresses,
    dnsUpStreams,
    exclusions,
    hostName,
    username,
    password,
    clientRandom,
    certificate,
    upStreamProtocol,
    upStreamFallbackProtocol,
    antiDpi,
    antiDpiMode,
    tlsProfile,
    clientRandomAuthKey,
    antiDpiDesync,
    h2PaddingFrames,
    h2PaddingFramesMin,
    h2PaddingPerStream,
    h2PaddingMinBytes,
    h2PaddingMaxBytes,
    h2PaddingStreamBytes,
    h2PaddingSessionBytes,
    keepaliveIntervalSecs,
    keepaliveSignal,
    sessionLifetimeSecs,
    xhttpEnabled,
    xhttpPath,
    blockQuic,
    ruExit,
    hasIpv6,
    skipVerification,
  ]);
}
