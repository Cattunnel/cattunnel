import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/ru_lists/cidr_set.dart';
import 'package:trusttunnel/data/ru_lists/ru_lists_service.dart';

void main() {
  test('geosite domains: domain/full kept, the rest skipped', () {
    expect(
      RuListsService.parseGeositeDomains([
        '# comment',
        'domain:Sber.World',
        'full:checkip.amazonaws.com',
        'regexp:^.*\\.ru\$',
        'keyword:bank',
        'include:other',
        'plain.example.com',
        'domain:bad_domain',
        'domain:tagged.example.org @ads',
      ]),
      [
        'sber.world',
        '*.sber.world',
        'checkip.amazonaws.com',
        'plain.example.com',
        '*.plain.example.com',
        'tagged.example.org',
        '*.tagged.example.org',
      ],
    );
  });

  test('server address cut out of the lists, other networks untouched', () {
    final lists = RuLists(
      v4Cidrs: CidrSet.v4(['10.0.0.0/16', '10.1.2.0/24', '46.226.120.0/21']).toCidrs(),
      v6Cidrs: CidrSet.v6(['2a00::/16']).toCidrs(),
      domains: const ['a.ru'],
      updatedAt: null,
    ).without(['46.226.121.53', '2a00::1']);
    expect(lists.v4Cidrs.take(2), ['10.0.0.0/16', '10.1.2.0/24']);
    expect(lists.v4Cidrs.any((c) => c.startsWith('46.226.121.53/')), isFalse);
    expect(lists.v4Cidrs, containsAll(['46.226.121.52/32', '46.226.121.54/31', '46.226.120.0/24']));
    expect(lists.v6Cidrs, isNot(contains('2a00:0:0:0:0:0:0:0/16')));
    expect(lists.v6Cidrs, contains('2a00:0:0:0:0:0:0:0/128'));
  });

  test('cidrsWithout matches exact subtraction', () {
    final cidrs = CidrSet.v4(['5.45.192.0/18', '77.88.0.0/18', '213.180.192.0/19']).toCidrs();
    final cut = ['77.88.55.60', '1.1.1.1'];
    expect(
      cidrsWithout(cidrs, cut),
      CidrSet.v4(cidrs).subtract(CidrSet.v4(cut)).toCidrs(),
    );
    expect(identical(cidrsWithout(cidrs, ['1.1.1.1']), cidrs), isTrue);
  });

  test('OS routes: built-in v4 networks of /22 and wider, server kept in VPN', () {
    expect(
      RuListsService.routesFromRules(
        [
          '*.ru',
          '5.45.192.0/18',
          '46.226.122.0/24',
          '185.32.248.0/22',
          '2a02:6b8::/29',
          '194.85.207.201',
          ' 87.250.224.0/19 ',
        ],
        keepInVpn: ['87.250.230.1'],
      ),
      containsAll(['5.45.192.0/18', '185.32.248.0/22', '87.250.224.0/22', '87.250.230.0/32']),
    );
    final routes = RuListsService.routesFromRules(['46.226.122.0/24', '5.45.192.0/18']);
    expect(routes, ['5.45.192.0/18']);
    expect(
      RuListsService.routesFromRules([
        '*.ru',
        '46.226.122.0/24',
        '5.45.192.0/18',
        '194.85.207.201',
      ], everyNetwork: true),
      ['5.45.192.0/18', '46.226.122.0/24', '194.85.207.201/32'],
    );
  });

  test('app lists: plain and mihomo PROCESS-NAME formats', () {
    expect(
      RuListsService.parseAppList([
        '# c',
        'ru.sberbankmobile',
        '  - PROCESS-NAME,com.vk.im',
        'payload:',
        'bad name',
        'x',
      ]),
      {'ru.sberbankmobile', 'com.vk.im'},
    );
  });

  test('poisoned network sources are rejected, the cached copy stays', () {
    expect(RuListsService.rejectSource('runetfreedom_ru', '5.45.192.0/18\n0.0.0.0/0\n'), isNotNull);
    expect(RuListsService.rejectSource('ipverse_ru_v6', '2a02:6b8::/29\n::/0\n'), isNotNull);
    // 64 x /8 = 25% of IPv4: every line is narrow enough, the total isn't.
    final wide = [for (var i = 1; i <= 64; i++) '$i.0.0.0/8'].join('\n');
    expect(RuListsService.rejectSource('ipverse_ru_v4', wide), contains('% of IPv4'));
    expect(RuListsService.rejectSource('ipverse_ru_v4', '5.45.192.0/18\n77.88.0.0/18\n46.226.120.0/21\n'), isNull);
    // Many /16s adding up to a large share of global IPv6.
    final wide6 = [for (var i = 0; i < 400; i++) '2${(i ~/ 256).toRadixString(16)}${(i % 256).toRadixString(16).padLeft(2, '0')}::/16'].join('\n');
    expect(RuListsService.rejectSource('ipverse_ru_v6', wide6), contains('% of global IPv6'));
    expect(RuListsService.rejectSource('ipverse_ru_v6', '2a02:6b8::/29\n2a00:1148::/32\n'), isNull);
  });

  test('too-wide lines are dropped even from an old cached copy', () {
    expect(RuListsService.plausibleNetworkLine('0.0.0.0/0'), isFalse);
    expect(RuListsService.plausibleNetworkLine('10.0.0.0/7'), isFalse);
    expect(RuListsService.plausibleNetworkLine('95.108.128.0/17'), isTrue);
    expect(RuListsService.plausibleNetworkLine('::/0'), isFalse);
    expect(RuListsService.plausibleNetworkLine('2a02:6b8::/29'), isTrue);
    expect(RuListsService.plausibleNetworkLine('# comment'), isTrue);
  });

  test('downloaded domains: AI, Google, Meta and public suffixes never bypass', () {
    for (final rule in [
      'google.com',
      '*.youtube.com',
      'chatgpt.com',
      'api.openai.com',
      'claude.ai',
      'gemini.google.com',
      '*.instagram.com',
      'web.whatsapp.com',
      'co.uk',
      '*.com.tr',
      'perplexity.ai',
      '*.amazonaws.com',
      'torproject.org',
      '*.protonmail.com',
      'example.com',
    ]) {
      expect(RuListsService.allowedBypassDomain(rule), isFalse, reason: rule);
    }
    for (final rule in [
      'sberbank.ru',
      '*.gosuslugi.ru',
      'vk.com',
      'yandex.com',
      'com.ru',
      '*.msk.ru',
      'ozon.ru',
      'deepseek.com',
      'checkip.amazonaws.com',
    ]) {
      expect(RuListsService.allowedBypassDomain(rule), isTrue, reason: rule);
    }
  });

  test('a domain source that suddenly grows a lot is rejected', () {
    final before = [for (var i = 0; i < 100; i++) 'domain:site$i.ru'].join('\n');
    final after = [for (var i = 0; i < 400; i++) 'domain:site$i.ru'].join('\n');
    expect(RuListsService.rejectSource('hydraponique_category_ru', after, previous: before), isNotNull);
    expect(RuListsService.rejectSource('hydraponique_category_ru', before, previous: before), isNull);
  });
}
