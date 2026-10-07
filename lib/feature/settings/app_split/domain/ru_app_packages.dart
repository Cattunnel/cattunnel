/// Package prefixes that are Russian as a rule: ru.* / su.* (how Russian
/// developers usually name apps), Yandex and VK.
const ruAppPrefixes = <String>['ru.', 'su.', 'com.yandex.', 'com.vk.'];

/// Yandex Browser (com.yandex.browser and its beta/alpha/lite builds) always
/// stays in the VPN, even though it is Russian and the `com.yandex.` prefix and
/// the community lists would send it around the tunnel: for very many people
/// it is THE browser, so bypassing it would take almost all their traffic out
/// of the VPN. Yandex sites themselves still go direct by the domain rules.
bool keptInVpn(String package) => package == 'com.yandex.browser' || package.startsWith('com.yandex.browser.');

/// Candidates for "bypass the VPN" among [installed] packages: the prefixes
/// above, the known list below and [downloaded] (the community lists, see
/// RuListsService). Only a suggestion - the picker shows it for review.
/// [cnAppKeepInVpn] never counts: the community lists name TikTok too.
/// Neither does Yandex Browser ([keptInVpn]).
Set<String> suggestRuApps(Iterable<String> installed, {Set<String> downloaded = const {}}) => installed
    .where(
      (package) =>
          !cnAppKeepInVpn.contains(package) &&
          !keptInVpn(package) &&
          (ruAppPackages.contains(package) ||
              downloaded.contains(package) ||
              ruAppPrefixes.any(package.startsWith)),
    )
    .toSet();

/// Russian apps that tend to notice a VPN (banks, government services,
/// marketplaces, VK/Yandex/MAX) - the "Russian apps" button in the split
/// tunneling picker selects the installed ones. Only a starting point: the
/// person reviews the list before saving.
const ruAppPackages = <String>{
  // Banks and payments
  'ru.sberbankmobile',
  'com.idamob.tinkoff.android',
  'ru.alfabank.mobile.android',
  'ru.vtb24.mobilebanking.android',
  'ru.nspk.mirpay',
  // Government
  'ru.rostel',
  // Messengers, social
  'ru.oneme.app',
  'com.vkontakte.android',
  'ru.ok.android',
  'ru.mail.mailapp',
  // Yandex
  'ru.yandex.searchplugin',
  'ru.yandex.taxi',
  'ru.yandex.music',
  'ru.yandex.yandexmaps',
  'ru.yandex.market',
  'ru.kinopoisk',
  // Shops, services
  'ru.ozon.app.android',
  'com.wildberries.ru',
  'com.avito.android',
  'ru.dublgis.dublgisapp',
  'ru.hh.android',
  'ru.rutube.app',
  'ru.vk.store',
  // Found on family phones, missing from the community lists
  'com.citymobil',
  'com.gsgroup.tricoloronline.mobile',
  'com.programmisty.emiasapp',
  'com.region',
  'com.mvizlab.lucy.android.ru',
  'com.zvooq.openplay', // Zvuk (Sber)
  'com.swiftsoft.anixartd', // Anixart
  'xyz.anilabx.app', // AniLabX
  'pro.tdnm.gurmanica', // Karavaevy
  'com.amdteka', // Amediateka
  'com.dscontrol', // Avtoshkola-Kontrol
  // Found on a Galaxy S25 Ultra (Bashkortostan)
  'com.aisgorod.mpo.rb', // EIRC RB - utility payments
  'com.iserv.JKHMobileCabinet.BashRTS', // BashRTS
  'com.aptekarsk.pz', // Planeta Zdorovya pharmacies
  'com.platfomni.asna', // Asna.ru pharmacies
  'com.platfomni.saas.ma', // Megapteka
  'com.sephora.mobileapp', // Il de Beaute
  'com.ladygentleman.app', // lgCITY
  'com.adamas.adamas', // ADAMAS jewellery
  'tech.jm', // Dzhum (Joom's Russian app)
  'com.yclients.yplaces', // YPLACES (YCLIENTS)
  'com.eno.rirloyalty', // Pochyotny Gost loyalty
  // Found on a Galaxy S26 Ultra (on one community list at most)
  'com.ipspirates.ort', // Perviy kanal (geo-limited to Russia)
  'com.vgtrk.smotrim', // Smotrim (VGTRK, geo-limited)
  'com.maxim.internal', // Maxim taxi
  'com.ncloudtech.cloudoffice', // MyOffice Documents
  'com.zemingo.gulfstream', // Gulfstream security systems
  // Games with servers in Russia
  'com.tanksblitz',
  'com.gamesforfriends.trueorfalse.ru',
  'com.rstgames.durak',
  'com.teremok.influence',
  // Mobile operators
  'ru.mts.mymts',
  'ru.megafon.mlk',
  'ru.beeline.services',
};

/// Not Russian, but no reason to go through the VPN either: Uzbekistan's
/// services (uz.*) and local tools. Bypass automatically like the Chinese
/// ones - and, unlike the Russian ones, can be put back into the VPN.
const otherDirectPrefixes = <String>['uz.'];

const otherDirectPackages = <String>{
  'www.metro.com', // METRO Cash & Carry
  'market.ruplay.store', // RuMarket
  'com.arassanusga.ankar.group', // Ankar
  'air.StrelkaSDFREE', // Antiradar (Strelka)
  'com.nirkof.nds', // VAT calculator
  'sergeiv.plumberhandbook', // Plumber's handbook
  'mmy.first.myapplication433', // Electrician's handbook
  // Uzbek apps outside uz.* (the family's Uzbek phone)
  'al_quran.uzbek.koran.islamic.quran',
  'com.appsolbiz.coran.uzbekquran',
  'com.atlascoder.android.dollaruz',
  'com.qalpampir.qalampir.uz',
  'com.rasulolloh_101.duolari',
  'com.sabgames.ramazonuz',
  'namaz.in.uzbek.AOVHBEPMDHS',
  'zikr.arabic.uz.zikrlar',
  'com.aasnsprojects.salovotvi',
};

/// Other direct packages among [installed].
Set<String> suggestOtherApps(Iterable<String> installed) => installed
    .where((package) => otherDirectPackages.contains(package) || otherDirectPrefixes.any(package.startsWith))
    .toSet();

/// Chinese services and phone vendors' own apps: their servers are in China
/// or at the vendor and reachable from Russia, so the VPN only adds a detour.
const cnAppPrefixes = <String>[
  // vivo / iQOO
  'com.vivo.', 'com.bbk.', 'com.iqoo.', 'com.vos.', 'vivo.', 'com.kaixinkan.',
  // Xiaomi, Huawei / Honor, Oppo / Realme / OnePlus, Meizu
  'com.xiaomi.', 'com.miui.', 'com.huawei.', 'com.hihonor.',
  'com.oppo.', 'com.coloros.', 'com.oplus.', 'com.heytap.', 'com.realme.', 'com.meizu.',
  // Services
  'com.baidu.', 'com.tencent.', 'com.ss.android.', 'com.bytedance.', 'com.alibaba.', 'com.taobao.',
  'com.alipay.', 'com.eg.android.AlipayGphone', 'com.xingin.', 'com.netease.', 'com.sina.', 'com.qihoo.',
  'com.unionpay.', 'com.chaozh.', 'com.xtc.', 'cn.', 'com.amap.', 'com.moonshot.', 'com.deepseek.',
  // Chinese standards (IFAA biometrics, WAPI, eID)
  'org.ifaa.', 'com.wapi.', 'com.rongcard.',
  // vivo system services under neutral names (seen on a vivo V2547DA)
  'com.mobile.iroaming', 'com.mobile.cos.iroaming', 'com.os.callservice', 'com.newcall', 'com.ringclip',
  'com.dcservice', 'com.fido.client', 'com.mobiletools.systemhelper', 'com.touchscreen.', 'com.vivotouchscreen.',
  'com.funtouch.', 'com.yozo.', // FuntouchOS, Yozo Office (preinstalled on Chinese vivo)
];

/// Never auto-selected - not by the prefixes above, not by the Russian
/// lists (the community lists name TikTok): TikTok and CapCut are limited
/// from Russia, the VPN is what makes them work.
const cnAppKeepInVpn = <String>{'com.zhiliaoapp.musically', 'com.ss.android.ugc.trill', 'com.lemon.lvoverseas'};

/// Chinese and vendor packages among [installed].
Set<String> suggestCnApps(Iterable<String> installed) => installed
    .where((package) => !cnAppKeepInVpn.contains(package) && cnAppPrefixes.any(package.startsWith))
    .toSet();
