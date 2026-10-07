import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Licenses of code that Flutter doesn't list on its own: libraries compiled
/// into the native VPN engine (`libtrusttunnel_android.so`) and Android
/// (Gradle) dependencies. Dart packages and the Flutter engine are added by
/// Flutter automatically.
///
/// Texts live in `assets/licenses/`, fetched from each project at the version
/// the engine/app pins (see TrustTunnelClient `conanfile.py`, DnsLibs and
/// NativeLibsCommon for the native side, `:app:dependencies` for Android).
const _entries = <(List<String>, String)>[
  // Native VPN engine
  (['ada'], 'ada.txt'),
  (['boringssl'], 'boringssl.txt'),
  (['ByeDPI (anti-DPI techniques, adapted)'], 'byedpi.txt'),
  (['brotli'], 'brotli.txt'),
  (['cxxopts'], 'cxxopts.txt'),
  (['fmt'], 'fmt.txt'),
  (['http_parser'], 'http_parser.txt'),
  (['klib'], 'klib.txt'),
  (['ldns'], 'ldns.txt'),
  (['libevent'], 'libevent.txt'),
  (['libsodium'], 'libsodium.txt'),
  (['libuv'], 'libuv.txt'),
  (['llhttp'], 'llhttp.txt'),
  (['lwip'], 'lwip.txt'),
  (['magic_enum'], 'magic_enum.txt'),
  (['nghttp2'], 'nghttp2.txt'),
  (['nghttp3'], 'nghttp3.txt'),
  (['ngtcp2'], 'ngtcp2.txt'),
  (['nlohmann_json'], 'nlohmann_json.txt'),
  (['pcre2'], 'pcre2.txt'),
  (['tldregistry (Chromium)'], 'chromium_tldregistry.txt'),
  (['tldregistry (Public Suffix List)'], 'publicsuffix_list.txt'),
  (['toml++'], 'tomlplusplus.txt'),
  (['zlib'], 'zlib.txt'),
  // Android libraries
  (['ktoml'], 'ktoml.txt'),
  (['protobuf (datastore)'], 'protobuf.txt'),
  (['reactive-streams'], 'reactive_streams.txt'),
  (['slf4j'], 'slf4j.txt'),
  (['sqlite'], 'sqlite.txt'),
  (['TrustTunnel engine, AndroidX, Kotlin and other Apache-2.0 components'], 'apache_2_0_components.txt'),
  (['Google ML Kit, Play services'], 'google_proprietary.txt'),
];

void registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (packages, file) in _entries) {
      yield LicenseEntryWithLineBreaks(packages, await rootBundle.loadString('assets/licenses/$file'));
    }
  });
}
