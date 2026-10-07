import 'dart:io';

import 'package:flutter/services.dart';
import 'package:trusttunnel/feature/security/domain/desktop_ca_bundle.dart';

/// A CA the phone trusts beyond the stock system set: user-installed, or a
/// Russian Ministry of Digital Development ("Russian Trusted") root found
/// even among system ones.
class TrustedCaInfo {
  final String subject;
  final bool userInstalled;
  final bool russianTrusted;

  const TrustedCaInfo({required this.subject, required this.userInstalled, required this.russianTrusted});
}

class DeviceSecurityReport {
  final bool deviceSecure;
  final String? privateDnsMode;
  final String? privateDnsHost;
  final bool adbEnabled;
  final bool batteryOptimizationIgnored;

  const DeviceSecurityReport({
    required this.deviceSecure,
    required this.privateDnsMode,
    required this.privateDnsHost,
    required this.adbEnabled,
    required this.batteryOptimizationIgnored,
  });

  /// `hostname` = the user pinned a specific DNS-over-TLS server.
  bool get customPrivateDns => privateDnsMode == 'hostname';
}

class VpnNetworkReport {
  final bool vpnActive;
  final bool defaultRouteV4;
  final bool defaultRouteV6;
  final List<String> vpnDnsServers;
  final bool underlyingHasGlobalIpv6;

  /// Whether Android validated CatTunnel's VPN network; null - no such
  /// network (or the platform doesn't say).
  final bool? vpnValidated;
  final String manufacturer;
  final String brand;

  const VpnNetworkReport({
    required this.vpnActive,
    required this.defaultRouteV4,
    required this.defaultRouteV6,
    required this.vpnDnsServers,
    required this.underlyingHasGlobalIpv6,
    this.vpnValidated,
    this.manufacturer = '',
    this.brand = '',
  });

  /// BBK Electronics phones: vivo, iQOO, OPPO, realme, OnePlus.
  bool get isBbk => const {'vivo', 'iqoo', 'oppo', 'realme', 'oneplus'}.any(
    (name) => manufacturer.toLowerCase().contains(name) || brand.toLowerCase().contains(name),
  );

  /// The phone has real IPv6 connectivity but the tunnel doesn't claim ::/0 -
  /// IPv6 traffic goes around the VPN.
  bool get ipv6Leak => vpnActive && underlyingHasGlobalIpv6 && !defaultRouteV6;
}

enum SecuritySettingsTarget { vpn, security, network, developer, battery, lock }

/// Dart side of `cattunnel/security` (android/.../SecurityChannel.kt).
/// Every call degrades to a neutral answer off Android.
abstract final class SecurityPlatform {
  static const _channel = MethodChannel('cattunnel/security');

  /// System roots minus the Russian Ministry ones (Windows/Linux:
  /// DesktopCaBundle).
  static Future<String?> systemCaBundle() async =>
      Platform.isAndroid ? _call<String>('systemCaBundle') : DesktopCaBundle.build();

  static Future<List<TrustedCaInfo>> certificateReport() async {
    final raw = await _call<List<Object?>>('certificateReport') ?? const [];

    return [
      for (final item in raw.cast<Map<Object?, Object?>>())
        TrustedCaInfo(
          subject: item['subject'] as String? ?? '',
          userInstalled: item['user'] as bool? ?? false,
          russianTrusted: item['russianTrusted'] as bool? ?? false,
        ),
    ];
  }

  static Future<DeviceSecurityReport?> deviceReport() async {
    final raw = await _call<Map<Object?, Object?>>('deviceReport');
    if (raw == null) {
      return null;
    }

    return DeviceSecurityReport(
      deviceSecure: raw['deviceSecure'] as bool? ?? false,
      privateDnsMode: raw['privateDnsMode'] as String?,
      privateDnsHost: raw['privateDnsHost'] as String?,
      adbEnabled: raw['adbEnabled'] as bool? ?? false,
      batteryOptimizationIgnored: raw['batteryOptimizationIgnored'] as bool? ?? false,
    );
  }

  static Future<VpnNetworkReport?> vpnNetworkReport() async {
    final raw = await _call<Map<Object?, Object?>>('vpnNetworkReport');
    if (raw == null) {
      return null;
    }

    return VpnNetworkReport(
      vpnActive: raw['vpnActive'] as bool? ?? false,
      defaultRouteV4: raw['defaultRouteV4'] as bool? ?? false,
      defaultRouteV6: raw['defaultRouteV6'] as bool? ?? false,
      vpnDnsServers: (raw['vpnDnsServers'] as List<Object?>? ?? const []).whereType<String>().toList(),
      underlyingHasGlobalIpv6: raw['underlyingHasGlobalIpv6'] as bool? ?? false,
      vpnValidated: raw['vpnValidated'] as bool?,
      manufacturer: raw['manufacturer'] as String? ?? '',
      brand: raw['brand'] as String? ?? '',
    );
  }

  static Future<void> openSettings(SecuritySettingsTarget target) => _call<bool>('openSettings', target.name);

  static Future<bool> isDisguised() async => await _call<bool>('isDisguised') ?? false;

  static Future<void> setDisguised(bool disguised) => _call<void>('setDisguised', disguised);

  /// Stops the VPN and wipes all app data; the process is killed.
  static Future<void> wipeAllData() => _call<void>('wipeAllData');

  static Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      // A native failure must not hang a screen - treat as "unknown".
      return null;
    }
  }
}
