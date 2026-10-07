import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/feature/vpn/domain/tls_profile_auto.dart';

void main() {
  test('default browsers map to the engine profile they resemble', () {
    for (final (browser, profile) in const [
      ('com.android.chrome', 'chrome'),
      ('com.yandex.browser', 'chrome'),
      ('com.sec.android.app.sbrowser', 'chrome'),
      ('ChromeHTML', 'chrome'),
      ('MSEdgeHTM', 'chrome'),
      ('YandexHTML', 'chrome'),
      ('google-chrome.desktop', 'chrome'),
      ('org.mozilla.firefox', 'firefox'),
      ('FirefoxURL-308046B0AF4A39CB', 'firefox'),
      ('firefox-esr.desktop', 'firefox'),
      ('librewolf.desktop', 'firefox'),
    ]) {
      expect(TlsProfileAuto.profileForBrowser(browser), profile, reason: browser);
    }
  });

  test('unknown or missing browser: no guess, the caller draws', () {
    expect(TlsProfileAuto.profileForBrowser(null), isNull);
    expect(TlsProfileAuto.profileForBrowser(''), isNull);
    expect(TlsProfileAuto.profileForBrowser('com.example.reader'), isNull);
  });
}
