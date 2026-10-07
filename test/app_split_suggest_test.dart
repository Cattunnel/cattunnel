import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/feature/settings/app_split/domain/auto_bypass_apps.dart';
import 'package:trusttunnel/feature/settings/app_split/domain/ru_app_packages.dart';

void main() {
  test('suggests known Russian apps and ru.* packages only', () {
    expect(
      suggestRuApps([
        'com.idamob.tinkoff.android',
        'ru.some.newbank',
        'com.vkontakte.android',
        'org.telegram.messenger',
        'com.google.android.youtube',
      ]),
      {'com.idamob.tinkoff.android', 'ru.some.newbank', 'com.vkontakte.android'},
    );
  });

  test('prefixes and downloaded lists', () {
    expect(
      suggestRuApps(['su.game', 'com.yandex.disk', 'com.vk.im', 'com.x.bank', 'com.foreign'], downloaded: {'com.x.bank'}),
      {'su.game', 'com.yandex.disk', 'com.vk.im', 'com.x.bank'},
    );
  });

  test('Yandex Browser stays in the VPN: prefix, known list and community lists notwithstanding', () {
    const browsers = ['com.yandex.browser', 'com.yandex.browser.beta', 'com.yandex.browser.alpha', 'com.yandex.browser.lite'];
    expect(suggestRuApps([...browsers, 'ru.yandex.searchplugin'], downloaded: browsers.toSet()), {'ru.yandex.searchplugin'});
  });

  test('Uzbek apps and local tools are "other direct", not Russian', () {
    final installed = ['uz.kun.app', 'uz.uztelecom.telecom', 'com.qalpampir.qalampir.uz', 'com.nirkof.nds', 'com.whatsapp'];
    expect(suggestOtherApps(installed), {'uz.kun.app', 'uz.uztelecom.telecom', 'com.qalpampir.qalampir.uz', 'com.nirkof.nds'});
    expect(suggestRuApps(installed), isEmpty);
  });

  test('Russian apps always bypass; other automatic ones unless put back into the VPN', () {
    const auto = AutoBypassApps(ru: {'ru.sberbankmobile'}, other: {'com.tencent.mm', 'uz.kun.app'});
    expect(auto.bypassing(otherOn: true), {'ru.sberbankmobile', 'com.tencent.mm', 'uz.kun.app'});
    expect(auto.bypassing(otherOn: true, forcedVpn: ['uz.kun.app', 'ru.sberbankmobile']), {'ru.sberbankmobile', 'com.tencent.mm'});
    expect(auto.bypassing(otherOn: false), {'ru.sberbankmobile'});
  });

  test('TikTok stays in the VPN even when a Russian list names it', () {
    expect(
      suggestRuApps(['com.zhiliaoapp.musically', 'com.x.bank'], downloaded: {'com.zhiliaoapp.musically', 'com.x.bank'}),
      {'com.x.bank'},
    );
  });

  test('Chinese and vendor apps, TikTok kept in the VPN', () {
    expect(
      suggestCnApps([
        'com.vivo.appstore',
        'com.bbk.theme',
        'com.ss.android.ugc.aweme',
        'com.ss.android.ugc.trill',
        'com.zhiliaoapp.musically',
        'cn.com.omronhealthcare.omronplus.vivo',
        'com.samsung.android.app.notes',
        'com.google.android.gm',
      ]),
      {'com.vivo.appstore', 'com.bbk.theme', 'com.ss.android.ugc.aweme', 'cn.com.omronhealthcare.omronplus.vivo'},
    );
  });
}
