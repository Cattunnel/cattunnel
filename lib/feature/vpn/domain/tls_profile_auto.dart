import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:win32/win32.dart';

/// What "auto" (ServerData.tlsProfileAuto) resolved to on this device.
class TlsProfileChoice {
  /// chrome / firefox / safari - an engine `tls_profile`.
  final String profile;

  /// The default browser it was taken from (package, ProgId or .desktop
  /// name); null - none found, [profile] was drawn at random.
  final String? browser;

  const TlsProfileChoice(this.profile, this.browser);
}

/// The TLS fingerprint "auto": look like this device's default browser, so
/// the tunnel's handshake matches what the same address shows anyway.
///
/// Decided once and stored - never changed on errors or retries: per the
/// June 2026 ТСПУ reports, switching fingerprints during a freeze adds a
/// 600 s penalty. Only [redetect] (a button in the server form) or a
/// reinstall picks again. The browser name stays on the device.
abstract final class TlsProfileAuto {
  static const _profileKey = 'tls_profile_auto';
  static const _browserKey = 'tls_profile_auto_browser';
  static const _channel = MethodChannel('cattunnel/apps');

  /// The engine profile for a server's setting: its own pick, or this
  /// device's "auto".
  static Future<String> resolve(String serverProfile) async =>
      ServerData.tlsProfiles.contains(serverProfile) ? serverProfile : (await current()).profile;

  static Future<TlsProfileChoice> current() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_profileKey);
    if (stored != null && ServerData.tlsProfiles.contains(stored)) {
      return TlsProfileChoice(stored, preferences.getString(_browserKey));
    }

    return redetect();
  }

  static Future<TlsProfileChoice>? _redetecting;

  /// Looks for the default browser again. Taps while a lookup runs share it.
  /// With no browser to go by, an earlier draw is kept: drawing again on
  /// every tap would flip the fingerprint between chrome and firefox.
  static Future<TlsProfileChoice> redetect() => _redetecting ??= _redetect().whenComplete(() => _redetecting = null);

  static Future<TlsProfileChoice> _redetect() async {
    final preferences = await SharedPreferences.getInstance();
    final browser = await _defaultBrowser() ?? await _onlyBrowserFamily();
    final stored = preferences.getString(_profileKey);
    final found = profileForBrowser(browser);
    final choice = found != null
        ? TlsProfileChoice(found, browser)
        : TlsProfileChoice(ServerData.tlsProfiles.contains(stored) ? stored! : _draw(), null);
    await preferences.setString(_profileKey, choice.profile);
    if (choice.browser == null) {
      await preferences.remove(_browserKey);
    } else {
      await preferences.setString(_browserKey, choice.browser!);
    }

    return choice;
  }

  /// No default browser set (Android asks every time): if every installed
  /// browser is of one family, that family is what any link opens in anyway.
  static Future<String?> _onlyBrowserFamily() async {
    if (!Platform.isAndroid) return null;
    try {
      final browsers = await _channel.invokeListMethod<String>('browsers') ?? const [];
      final placed = browsers.where((b) => profileForBrowser(b) != null).toList();
      final families = placed.map(profileForBrowser).toSet();

      return families.length == 1 ? placed.first : null;
    } on Object {
      return null;
    }
  }

  /// Chromium-based browsers (Chrome, Yandex, Edge, Opera, Samsung, Brave,
  /// Vivaldi...) share BoringSSL and look like Chrome; Firefox forks like
  /// Firefox. Null - not a browser we can place.
  static String? profileForBrowser(String? browser) {
    final id = browser?.toLowerCase();
    if (id == null || id.isEmpty) return null;
    const firefox = [
      'firefox',
      'mozilla',
      'librewolf',
      'waterfox',
      'floorp',
      'fennec',
      'iceraven',
      'ironfox',
      'torbrowser',
    ];
    const chrome = [
      'chrome', 'chromium', 'yandex', 'msedge', 'edge', 'opera', 'brave', 'vivaldi', //
      'sbrowser', 'samsung', 'huawei.browser', 'miui.browser', 'mi.globalbrowser', 'heytap.browser', 'ucmobile',
    ];
    if (firefox.any(id.contains)) return 'firefox';
    if (id.contains('safari')) return 'safari';
    if (chrome.any(id.contains)) return 'chrome';

    return null;
  }

  /// No browser found: weighted like Russian desktop/mobile use - Chromium
  /// browsers dominate, Firefox is rare (an even split would stand out).
  static String _draw() => Random.secure().nextInt(100) < 75 ? 'chrome' : 'firefox';

  static Future<String?> _defaultBrowser() async {
    try {
      if (Platform.isAndroid) {
        return await _channel.invokeMethod<String>('defaultBrowser');
      }
      if (Platform.isWindows) {
        return _windowsHttpsProgId();
      }
      if (Platform.isLinux) {
        final result = await Process.run('xdg-settings', ['get', 'default-web-browser']);
        final name = '${result.stdout}'.trim();

        return result.exitCode == 0 && name.isNotEmpty ? name : null;
      }
    } on Object {
      // No channel / tool: fall back to the draw.
    }

    return null;
  }

  /// HKCU\...\UrlAssociations\https\UserChoice\ProgId (ChromeHTML,
  /// FirefoxURL-..., MSEdgeHTM, YandexHTML...) read in-process: running
  /// `reg.exe` from a GUI app would flash a console window.
  static String? _windowsHttpsProgId() => using((arena) {
    final size = arena<Uint32>()..value = 512;
    final buffer = arena<Uint16>(256).cast<Utf16>();
    final status = RegGetValue(
      HKEY_CURRENT_USER,
      r'Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice'.toNativeUtf16(allocator: arena),
      'ProgId'.toNativeUtf16(allocator: arena),
      RRF_RT_REG_SZ,
      nullptr,
      buffer,
      size,
    );

    return status == ERROR_SUCCESS ? buffer.toDartString() : null;
  });
}
