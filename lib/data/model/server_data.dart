import 'package:flutter/foundation.dart';
import 'package:trusttunnel/common/models/value_data.dart';
import 'package:trusttunnel/data/model/certificate.dart';
import 'package:trusttunnel/data/model/vpn_protocol.dart';
import 'package:vpn_plugin/domain/desync_string.dart';

/// {@template server}
/// A fully resolved VPN server configuration used by the app.
///
/// `Server` combines server connection credentials and transport parameters
/// with the associated []. This is a convenient domain model for
/// UI and business logic where you need both server details and routing rules
/// in one place.
///
/// Instances are immutable and use value-based equality.
/// {@endtemplate}
@immutable
class ServerData {
  /// User-visible server name.
  final String name;

  /// Server IP address (usually IPv4/IPv6 literal as stored by the app).
  final String ipAddress;

  /// Server host name used for TLS (SNI / certificate verification).
  final String domain;

  /// Username used for authentication.
  final String username;

  /// Password used for authentication.
  final String password;

  /// Transport protocol used to communicate with the server.
  final VpnProtocol vpnProtocol;

  /// DNS upstream addresses associated with this server.
  ///
  /// The list is expected to be treated as immutable by callers.
  final List<String> dnsServers;

  /// Routing profile applied when connecting to this server.
  final String routingProfileId;

  /// Whether this server is marked as the currently selected one.
  final bool selected;

  final Certificate? certificate;

  final bool ipv6;

  /// Engine anti-DPI: the first byte of the TLS ClientHello goes out alone,
  /// the rest 25 ms later, so a filter reading the SNI from one packet
  /// misses it. HTTP/2 (TCP) only.
  final bool antiDpi;

  /// With [antiDpi], how the ClientHello goes out (own engine build, patch
  /// 0001-anti-dpi-desync): 0 - the split above, 1..3 - the DPI2 techniques
  /// (engine `anti_dpi_mode`), [antiDpiAuto] - 1, 2, 3 in turn, remembering
  /// what worked for this server and network (see AntiDpiAuto). The upstream
  /// engine ignores 1..3 and does the split.
  final int antiDpiMode;

  static const antiDpiAuto = 4;

  /// [antiDpiMode] for the split in [antiDpiDesync].
  static const antiDpiCustom = 5;

  /// With [antiDpiCustom]: a custom split in byedpi syntax (engine
  /// `anti_dpi_desync`, see DesyncString), normalized; empty otherwise.
  final String antiDpiDesync;

  /// TLS ClientHello fingerprint the engine mimics (engine 1.3 `tls_profile`):
  /// [tlsProfileAuto] - this device's default browser (TlsProfileAuto), or
  /// one of [tlsProfiles].
  final String tlsProfile;

  static const tlsProfileAuto = '';

  static const tlsProfiles = ['chrome', 'firefox', 'safari', 'okhttp'];

  /// The mode the engine gets: 0 without [antiDpi] or for an unknown value.
  int get engineAntiDpiMode => antiDpi && antiDpiMode >= 1 && antiDpiMode <= 3 ? antiDpiMode : 0;

  /// HTTP/2 padding: the first this many frames of a connection carry
  /// 0-255 random bytes (engine `h2_padding_frames`, own build); 0 - off.
  /// Hides the sizes of the tunnel's first requests.
  final int h2PaddingFrames;

  /// What "on" means in the form.
  static const h2PaddingDefaultFrames = 8;

  /// QUIC off: the engine refuses UDP to port 443 (`block_quic`, own build),
  /// browsers and apps fall back to TCP inside the tunnel.
  final bool blockQuic;

  /// The custom split the engine gets: empty unless [antiDpiCustom] with a
  /// valid string (an invalid one would make the engine reject the key).
  String get engineAntiDpiDesync =>
      antiDpi && antiDpiMode == antiDpiCustom && DesyncString.validate(antiDpiDesync) == null
      ? DesyncString.normalize(antiDpiDesync)
      : '';

  /// A key with a Russian exit, for people abroad: only Russian apps go
  /// through it, everything else directly (the reverse of the usual rule).
  final bool ruExit;

  final String? tlsPrefix;

  final String? customSni;

  /// Display name of the subscription that manages this server, if any.
  ///
  /// `null` means the server was added manually and is never touched by a
  /// subscription refresh.
  final String? subscriptionName;

  /// {@macro server}
  const ServerData({
    required this.name,
    required this.ipAddress,
    required this.domain,
    required this.username,
    required this.password,
    required this.vpnProtocol,
    required this.dnsServers,
    required this.routingProfileId,
    required this.ipv6,
    this.antiDpi = false,
    this.antiDpiMode = 0,
    this.tlsProfile = tlsProfileAuto,
    this.antiDpiDesync = '',
    this.h2PaddingFrames = 0,
    this.blockQuic = false,
    this.ruExit = false,
    this.certificate,
    this.tlsPrefix,
    this.customSni,
    this.selected = false,
    this.subscriptionName,
  });

  const ServerData.empty({
    this.name = '',
    this.ipAddress = '',
    this.domain = '',
    this.username = '',
    this.password = '',
    this.vpnProtocol = VpnProtocol.http2,
    this.dnsServers = const [],
    this.routingProfileId = '',
    this.ipv6 = true,
    this.antiDpi = false,
    this.antiDpiMode = 0,
    this.tlsProfile = tlsProfileAuto,
    this.antiDpiDesync = '',
    this.h2PaddingFrames = 0,
    this.blockQuic = false,
    this.ruExit = false,
    this.certificate,
    this.tlsPrefix,
    this.customSni,
    this.selected = false,
    this.subscriptionName,
  });

  @override
  int get hashCode => Object.hashAll([
    name,
    ipAddress,
    domain,
    username,
    password,
    vpnProtocol,
    Object.hashAll(dnsServers),
    routingProfileId,
    selected,
    certificate,
    ipv6,
    antiDpi,
    antiDpiMode,
    tlsProfile,
    antiDpiDesync,
    h2PaddingFrames,
    blockQuic,
    ruExit,
    tlsPrefix,
    customSni,
    subscriptionName,
  ]);

  @override
  String toString() =>
      'ServerData('
      'name: $name, '
      'ipAddress: $ipAddress, '
      'domain: $domain, '
      'customSni: $customSni, '
      'username: $username, '
      'vpnProtocol: $vpnProtocol, '
      'dnsServers: $dnsServers, '
      'routingProfile: $routingProfileId, '
      'selected: $selected,'
      'ipv6: $ipv6,'
      'antiDpi: $antiDpi,'
      'antiDpiMode: $antiDpiMode,'
      'tlsProfile: $tlsProfile,'
      'antiDpiDesync: $antiDpiDesync,'
      'h2PaddingFrames: $h2PaddingFrames,'
      'blockQuic: $blockQuic,'
      'ruExit: $ruExit,'
      'tlsPrefix: $tlsPrefix,'
      'certificate: $certificate,'
      'subscriptionName: $subscriptionName,'
      ')';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ServerData &&
        other.name.trim() == name.trim() &&
        other.ipAddress == ipAddress &&
        other.domain == domain &&
        other.username == username &&
        other.password == password &&
        other.vpnProtocol == vpnProtocol &&
        listEquals(other.dnsServers, dnsServers) &&
        other.routingProfileId == routingProfileId &&
        other.selected == selected &&
        other.ipv6 == ipv6 &&
        other.antiDpi == antiDpi &&
        other.antiDpiMode == antiDpiMode &&
        other.tlsProfile == tlsProfile &&
        other.antiDpiDesync == antiDpiDesync &&
        other.h2PaddingFrames == h2PaddingFrames &&
        other.blockQuic == blockQuic &&
        other.ruExit == ruExit &&
        other.tlsPrefix == tlsPrefix &&
        other.certificate == certificate &&
        other.customSni == customSni &&
        other.subscriptionName == subscriptionName;
  }

  /// Creates a copy of this server with the given fields replaced.
  ///
  /// Fields that are not provided retain their original values.
  ServerData copyWith({
    String? name,
    String? ipAddress,
    String? domain,
    String? username,
    String? password,
    VpnProtocol? vpnProtocol,
    List<String>? dnsServers,
    String? routingProfileId,
    bool? selected,
    bool? ipv6,
    bool? antiDpi,
    int? antiDpiMode,
    String? tlsProfile,
    String? antiDpiDesync,
    int? h2PaddingFrames,
    bool? blockQuic,
    bool? ruExit,
    ValueData<Certificate>? certificate,
    ValueData<String>? tlsPrefix,
    ValueData<String>? customSni,
  }) => ServerData(
    name: name ?? this.name,
    ipAddress: ipAddress ?? this.ipAddress,
    domain: domain ?? this.domain,
    username: username ?? this.username,
    password: password ?? this.password,
    vpnProtocol: vpnProtocol ?? this.vpnProtocol,
    dnsServers: dnsServers ?? this.dnsServers,
    routingProfileId: routingProfileId ?? this.routingProfileId,
    selected: selected ?? this.selected,
    ipv6: ipv6 ?? this.ipv6,
    antiDpi: antiDpi ?? this.antiDpi,
    antiDpiMode: antiDpiMode ?? this.antiDpiMode,
    tlsProfile: tlsProfile ?? this.tlsProfile,
    antiDpiDesync: antiDpiDesync ?? this.antiDpiDesync,
    h2PaddingFrames: h2PaddingFrames ?? this.h2PaddingFrames,
    blockQuic: blockQuic ?? this.blockQuic,
    ruExit: ruExit ?? this.ruExit,
    certificate: certificate != null ? certificate.value : this.certificate,
    tlsPrefix: tlsPrefix != null ? tlsPrefix.value : this.tlsPrefix,
    customSni: customSni != null ? customSni.value : this.customSni,
    subscriptionName: subscriptionName,
  );
}
