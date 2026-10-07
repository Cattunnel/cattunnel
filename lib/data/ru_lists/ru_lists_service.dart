import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:adguard_logger/adguard_logger.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:trusttunnel/data/ru_lists/cidr_set.dart';

/// Russian networks and domains for "Russian services bypass the VPN", on
/// top of the built-in list (assets/routing_presets/ru_services.txt):
///
/// - runetfreedom/geoip `text/ru.txt` - geoip:ru, v4 + v6 (CC-BY-SA-4.0, the
///   list Chimera, teapod-stream and our servers' antiblock use);
/// - ipverse/rir-ip - RU networks from the registries (v4, v6);
/// - hydraponique/roscomvpn-geosite `data/category-ru` - domains (MIT);
/// - three community lists of Russian Android apps (Lanakod, sh1shd,
///   legiz-ru) for the split tunneling auto-select - a package counts as
///   Russian when at least two of them list it (each has a few foreign
///   strays on its own).
///
/// Straight from the sources (GitHub, jsDelivr as the fallback - raw GitHub
/// is often blocked in Russia, and CatTunnel's own traffic doesn't go
/// through its tunnel), at most about once a day, cached per source so a
/// failed download keeps the last good copy.
class RuListsService {
  static const _refreshEvery = Duration(hours: 20);
  static const _timeout = Duration(seconds: 20);

  /// v4 networks of the built-in list this large (/22 and wider) become OS
  /// routes on Android: that traffic never enters the tunnel. The built-in
  /// list is the big Russian services (Yandex, VK, Sber...): 33 blocks, 96%
  /// of its addresses, ~380 routes after "everything minus these". Android
  /// takes every route in one Binder call and gets slow and flaky with
  /// thousands, and each scattered block costs ~10 routes whatever its size,
  /// so the downloaded lists (thousands of blocks) stay engine exclusions.
  static const routePrefixMax = 22;

  /// The merged lists, written after each download (see [_compile]) so a
  /// connect only reads finished lines.
  static const _compiledName = 'compiled.v1';

  static const _sources = <_Source>[
    _Source('runetfreedom_ru', [
      'https://raw.githubusercontent.com/runetfreedom/geoip/release/text/ru.txt',
      'https://cdn.jsdelivr.net/gh/runetfreedom/geoip@release/text/ru.txt',
    ]),
    _Source('ipverse_ru_v4', [
      'https://raw.githubusercontent.com/ipverse/rir-ip/master/country/ru/ipv4-aggregated.txt',
      'https://cdn.jsdelivr.net/gh/ipverse/rir-ip@master/country/ru/ipv4-aggregated.txt',
    ]),
    _Source('ipverse_ru_v6', [
      'https://raw.githubusercontent.com/ipverse/rir-ip/master/country/ru/ipv6-aggregated.txt',
      'https://cdn.jsdelivr.net/gh/ipverse/rir-ip@master/country/ru/ipv6-aggregated.txt',
    ]),
    _Source('apps_lanakod', [
      'https://raw.githubusercontent.com/Lanakod/russian-android-apps/master/apps/all.txt',
      'https://cdn.jsdelivr.net/gh/Lanakod/russian-android-apps@master/apps/all.txt',
    ]),
    _Source('apps_sh1shd', [
      'https://raw.githubusercontent.com/sh1shd/russia-apps-list/master/raw/happ-user.txt',
      'https://cdn.jsdelivr.net/gh/sh1shd/russia-apps-list@master/raw/happ-user.txt',
    ]),
    _Source('apps_legiz', [
      'https://raw.githubusercontent.com/legiz-ru/mihomo-rule-sets/main/other/ru-app-list.yaml',
      'https://cdn.jsdelivr.net/gh/legiz-ru/mihomo-rule-sets@main/other/ru-app-list.yaml',
    ]),
    _Source('hydraponique_category_ru', [
      'https://raw.githubusercontent.com/hydraponique/roscomvpn-geosite/master/data/category-ru',
      'https://cdn.jsdelivr.net/gh/hydraponique/roscomvpn-geosite@master/data/category-ru',
    ]),
  ];

  static const _domainSources = {'hydraponique_category_ru'};
  static const _appSources = {'apps_lanakod', 'apps_sh1shd', 'apps_legiz'};

  /// How many of the app lists must name a package.
  static const appListsQuorum = 2;

  RuLists? _cached;
  Future<RuLists>? _loading;
  Future<void>? _refreshing;

  /// Downloads the sources if the cache is older than about a day (or
  /// [force]). Never throws; a source that fails keeps its last copy.
  Future<void> refreshIfDue({bool force = false}) => _refreshing ??= _refresh(force).whenComplete(() {
    _refreshing = null;
  });

  Future<void> _refresh(bool force) async {
    final dir = await _dir();
    final stamp = File('${dir.path}/updated');
    if (!force && stamp.existsSync()) {
      final age = DateTime.now().difference(stamp.lastModifiedSync());
      if (age < _refreshEvery) return;
    }

    final texts = await Future.wait(_sources.map(_download));
    var anyOk = false;
    for (final (i, text) in texts.indexed) {
      if (text == null) continue;
      final file = File('${dir.path}/${_sources[i].name}.txt');
      final previous = file.existsSync() ? await file.readAsString() : null;
      final rejected = rejectSource(_sources[i].name, text, previous: previous);
      if (rejected != null) {
        // Implausible content (a compromised or broken source): keep the
        // last good copy, the VPN keeps working as before.
        logger.logInfo('Russian lists: ${_sources[i].name} rejected ($rejected), keeping the previous copy');
        continue;
      }
      await file.writeAsString(text);
      anyOk = true;
    }
    if (anyOk) {
      await stamp.writeAsString(DateTime.now().toIso8601String());
      final path = dir.path;
      await Isolate.run(() => _compile(path));
      _cached = null;
      _lastWithout = null;
    }
  }

  Future<String?> _download(_Source source) async {
    for (final url in source.urls) {
      try {
        final response = await http.get(Uri.parse(url)).timeout(_timeout);
        // A few KB at least: an error page or an empty file must not
        // replace a good cached copy.
        if (response.statusCode == 200 && response.bodyBytes.length > 1024) {
          return utf8.decode(response.bodyBytes, allowMalformed: true);
        }
      } on Object {
        // Next mirror.
      }
    }

    return null;
  }

  /// The merged lists from the cache (empty before the first download).
  /// [keepInVpn]: addresses that must never be bypassed (the VPN server).
  Future<RuLists> load({Iterable<String> keepInVpn = const []}) async {
    final base = _cached ??= await (_loading ??= _read().whenComplete(() => _loading = null));
    if (keepInVpn.isEmpty) return base;
    final key = (keepInVpn.toList()..sort()).join(',');
    if (_lastWithoutKey != key || _lastWithout == null || !identical(_lastWithoutBase, base)) {
      _lastWithout = base.without(keepInVpn);
      _lastWithoutKey = key;
      _lastWithoutBase = base;
    }

    return _lastWithout!;
  }

  // The last server-specific copy: reconnecting to the same server is the
  // common case.
  RuLists? _lastWithout;
  RuLists? _lastWithoutBase;
  String? _lastWithoutKey;

  /// Reads the compiled lists off the UI thread; compiles them first if
  /// only the sources are there (lists downloaded by an older version).
  Future<RuLists> _read() async {
    final path = (await _dir()).path;

    return Isolate.run(() {
      final compiled = File('$path/$_compiledName');
      if (!compiled.existsSync()) _compile(path);

      return _parseCompiled(path);
    });
  }

  /// Merges the downloaded sources into [_compiledName]: `#v4`, `#v6`,
  /// `#domains` (engine rules, `*.` variants included) and `#apps`
  /// sections, one entry per line. The CIDR arithmetic runs here, once per
  /// download, not on every connect.
  static void _compile(String path) {
    final ipLines = <String>[];
    final domains = <String>{};
    final appVotes = <String, int>{};
    for (final source in _sources) {
      final file = File('$path/${source.name}.txt');
      if (!file.existsSync()) continue;
      final lines = file.readAsLinesSync();
      if (_domainSources.contains(source.name)) {
        domains.addAll(parseGeositeDomains(lines).where(allowedBypassDomain));
      } else if (_appSources.contains(source.name)) {
        for (final package in parseAppList(lines)) {
          appVotes[package] = (appVotes[package] ?? 0) + 1;
        }
      } else {
        // Defense in depth for copies cached before the checks existed.
        ipLines.addAll(lines.where(plausibleNetworkLine));
      }
    }
    final apps = [
      for (final MapEntry(key: package, value: votes) in appVotes.entries)
        if (votes >= appListsQuorum) package,
    ]..sort();

    var v4 = CidrSet.v4(ipLines);
    var v6 = CidrSet.v6(ipLines);
    // Sources passed one by one; together they still must look like Russia.
    if (coverageV4(v4) > _maxMergedCoverageV4) v4 = CidrSet.v4(const []);
    if (coverageV6(v6) > _maxMergedCoverageV6) v6 = CidrSet.v6(const []);

    final out = StringBuffer()
      ..writeln('#v4')
      ..writeAll(v4.toCidrs(), '\n')
      ..writeln()
      ..writeln('#v6')
      ..writeAll(v6.toCidrs(), '\n')
      ..writeln()
      ..writeln('#domains')
      ..writeAll(domains.toList()..sort(), '\n')
      ..writeln()
      ..writeln('#apps')
      ..writeAll(apps, '\n')
      ..writeln();
    final tmp = File('$path/$_compiledName.tmp')..writeAsStringSync(out.toString());
    tmp.renameSync('$path/$_compiledName');
  }

  static RuLists _parseCompiled(String path) {
    final sections = <String, List<String>>{};
    var current = <String>[];
    final compiled = File('$path/$_compiledName');
    if (compiled.existsSync()) {
      for (final line in compiled.readAsLinesSync()) {
        if (line.startsWith('#')) {
          current = sections[line.substring(1)] = <String>[];
        } else if (line.isNotEmpty) {
          current.add(line);
        }
      }
    }
    final stamp = File('$path/updated');

    return RuLists(
      v4Cidrs: sections['v4'] ?? const [],
      v6Cidrs: sections['v6'] ?? const [],
      domains: sections['domains'] ?? const [],
      apps: {...?sections['apps']},
      updatedAt: stamp.existsSync() ? stamp.lastModifiedSync() : null,
    );
  }

  /// OS routes for Android from the built-in list [rules]: its v4 networks
  /// of [routePrefixMax] and wider, without [keepInVpn] (the VPN server).
  /// [everyNetwork]: all its v4 networks and addresses - on Android 13+ the
  /// engine excludes routes natively (patch 0004), one route per network,
  /// so the small VK CDN / WB / bank ones cost next to nothing there.
  static List<String> routesFromRules(
    Iterable<String> rules, {
    Iterable<String> keepInVpn = const [],
    bool everyNetwork = false,
  }) {
    final picked = everyNetwork ? rules : rules.where((r) => (cidrPrefixLength(r.trim()) ?? 33) <= routePrefixMax);

    return CidrSet.v4(picked).subtract(CidrSet.v4(keepInVpn)).toCidrs();
  }

  Future<Directory> _dir() async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/ru_lists');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    return dir;
  }

  // --- Plausibility of downloaded lists -------------------------------
  //
  // The lists come from third-party repositories. One poisoned line such as
  // 0.0.0.0/0 would otherwise become "bypass everything" and silently turn
  // the VPN off for everyone (security audit 2026-09-27, M-01/M-02).

  /// The largest Russian blocks are around /10-/12; nothing wider than
  /// /8 (IPv4) or /16 (IPv6) is a plausible "Russian network".
  static const _minPrefixV4 = 8;
  static const _minPrefixV6 = 16;

  /// Russia is about 1-2% of IPv4; a source covering more is broken.
  static const _maxCoverageV4 = 0.03;

  /// Share of the global unicast IPv6 space (2000::/3) a source may cover:
  /// Russia's real allocations are far below it; a poisoned list of /16s
  /// adding up to "all IPv6 around the VPN" is not (security audit run-2, #6).
  static const _maxCoverageV6 = 0.01;

  /// The same limits for all sources merged: several sources each just under
  /// the limit must not add up to much more.
  static const _maxMergedCoverageV4 = 0.05;
  static const _maxMergedCoverageV6 = 0.02;

  static double coverageV4(CidrSet set) => cidrSetAddressCount(set).toDouble() / 4294967296;

  static double coverageV6(CidrSet set) => cidrSetAddressCount(set).toDouble() / (BigInt.one << 125).toDouble();

  /// A domain source that grows this much in one refresh is suspicious.
  static const _maxDomainGrowth = 1.5;

  /// Whether a network line is narrow enough to be a Russian network
  /// (comments, blank and unparsable lines pass - the parser skips them).
  static bool plausibleNetworkLine(String raw) {
    final line = raw.trim();
    final slash = line.indexOf('/');
    if (slash < 0) return true;
    final prefix = int.tryParse(line.substring(slash + 1));
    if (prefix == null) return true;

    return prefix >= (line.contains(':') ? _minPrefixV6 : _minPrefixV4);
  }

  /// Why [text] (a fresh download of [name]) must not replace the cached
  /// copy, or null when it's plausible. [previous] is the cached copy.
  static String? rejectSource(String name, String text, {String? previous}) {
    final lines = const LineSplitter().convert(text);
    if (_appSources.contains(name)) return null;
    if (_domainSources.contains(name)) {
      final count = parseGeositeDomains(lines).length;
      final before = previous == null ? 0 : parseGeositeDomains(const LineSplitter().convert(previous)).length;
      if (before > 0 && count > before * _maxDomainGrowth + 50) return 'domains grew from $before to $count';

      return null;
    }
    final broad = lines.where((line) => !plausibleNetworkLine(line)).length;
    if (broad > 0) return '$broad network(s) wider than /$_minPrefixV4 (v4) or /$_minPrefixV6 (v6)';
    final coverage = coverageV4(CidrSet.v4(lines));
    if (coverage > _maxCoverageV4) return 'covers ${(coverage * 100).toStringAsFixed(1)}% of IPv4';
    final coverage6 = coverageV6(CidrSet.v6(lines));
    if (coverage6 > _maxCoverageV6) return 'covers ${(coverage6 * 100).toStringAsFixed(2)}% of global IPv6';

    return null;
  }

  /// Global services and public suffixes a downloaded "Russian" domain
  /// list must never send around the VPN: AI services, Google, Meta and
  /// other big foreign platforms.
  static const _neverBypassDomains = <String>{
    // AI
    'openai.com', 'chatgpt.com', 'oaistatic.com', 'oaiusercontent.com', 'anthropic.com', 'claude.ai', 'claude.com',
    'gemini.google.com', 'perplexity.ai', 'x.ai', 'grok.com', 'mistral.ai', 'huggingface.co',
    'midjourney.com', 'character.ai', 'poe.com', 'copilot.microsoft.com', 'cohere.com', 'together.ai', 'groq.com',
    'openrouter.ai', 'stability.ai', 'runwayml.com', 'suno.com', 'elevenlabs.io', 'notebooklm.google',
    // Google
    'google.com', 'googleapis.com', 'gstatic.com', 'googleusercontent.com', 'googlevideo.com', 'youtube.com',
    'youtu.be', 'ytimg.com', 'ggpht.com', 'gmail.com', 'android.com', 'goo.gl', 'g.co', 'googleadservices.com',
    'doubleclick.net', 'googlesyndication.com', 'google-analytics.com', 'firebaseio.com', 'firebase.google.com',
    'app.goo.gl', 'withgoogle.com', 'google', 'gvt1.com', 'gvt2.com',
    // Meta
    'facebook.com', 'fb.com', 'fbcdn.net', 'fbsbx.com', 'facebook.net', 'instagram.com', 'cdninstagram.com',
    'whatsapp.com', 'whatsapp.net', 'wa.me', 'messenger.com', 'meta.com', 'meta.ai', 'threads.net', 'threads.com',
    'oculus.com',
    // Other big foreign platforms
    'apple.com', 'icloud.com', 'microsoft.com', 'live.com', 'office.com', 'windows.net', 'telegram.org', 't.me',
    'twitter.com', 'x.com', 'twimg.com', 'discord.com', 'discord.gg', 'cloudflare.com',
    'amazon.com', 'netflix.com', 'spotify.com', 'github.com', 'tiktok.com', 'signal.org', 'proton.me',
  };

  /// Shared hosting/CDN domains: a rule on the whole domain is refused, but
  /// a specific host under it is fine (the geosite list sends
  /// checkip.amazonaws.com directly on purpose).
  static const _neverBypassWholeDomains = <String>{
    'amazonaws.com',
    'cloudfront.net',
    'azureedge.net',
    'akamaiedge.net',
    'akamaihd.net',
    'fastly.net',
    'herokuapp.com',
    'vercel.app',
    'netlify.app',
    'github.io',
    'appspot.com',
    'workers.dev',
    'pages.dev',
  };

  /// Second-level public suffixes like co.uk / com.tr: a rule on one would
  /// send a whole country around the VPN. Russian ones (com.ru, msk.ru...)
  /// are fine.
  static const _publicSecondLevels = {'co', 'com', 'net', 'org', 'gov', 'edu', 'ac', 'or', 'ne', 'go', 'gob', 'gouv'};
  static const _russianTlds = {'ru', 'su', 'xn--p1ai', 'рф'};

  /// Russian services on foreign zones a downloaded list may send around the
  /// VPN (the domain or any subdomain). Any other foreign domain from a
  /// third-party list stays in the VPN: a poisoned list could otherwise make
  /// torproject.org or protonmail.com "Russian" (security audit run-2, #6).
  static const _verifiedForeignDomains = <String>{
    'vk.com', 'vk.me', 'vkontakte.com', 'userapi.com', 'vkuser.net', 'vk-cdn.net', 'mycdn.me',
    'yandex.com', 'yandex.net', 'yastatic.net', 'yandexcloud.net', 'yandex.cloud', 'yandex.st',
    'sberbank.com', 'avito.st', 'kaspersky.com', '2gis.com', 'deepseek.com', 'checkip.amazonaws.com',
  };

  /// Whether a downloaded domain rule may be used as a bypass rule.
  static bool allowedBypassDomain(String rule) {
    final domain = rule.startsWith('*.') ? rule.substring(2) : rule;
    final labels = domain.split('.');
    if (labels.length == 2 && _publicSecondLevels.contains(labels.first) && !_russianTlds.contains(labels.last)) {
      return false;
    }
    if (_neverBypassWholeDomains.contains(domain)) return false;
    for (var i = 0; i < labels.length; i++) {
      if (_neverBypassDomains.contains(labels.sublist(i).join('.'))) return false;
    }
    if (_russianTlds.contains(labels.last)) return true;
    for (var i = 0; i < labels.length - 1; i++) {
      if (_verifiedForeignDomains.contains(labels.sublist(i).join('.'))) return true;
    }

    return false;
  }

  /// Package names from a plain list or a mihomo `PROCESS-NAME,pkg` rule set.
  static Set<String> parseAppList(Iterable<String> lines) {
    final package = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$');
    final result = <String>{};
    for (final raw in lines) {
      var line = raw.split('#').first.trim();
      if (line.startsWith('-')) line = line.substring(1).trim();
      if (line.toUpperCase().startsWith('PROCESS-NAME,')) line = line.substring('PROCESS-NAME,'.length).trim();
      if (package.hasMatch(line)) result.add(line);
    }

    return result;
  }

  /// `domain:x` / `full:x` lines of a v2fly-style geosite source as engine
  /// exclusion rules (`x` and `*.x` for domain:, `x` for full:); regexp,
  /// keyword and include entries have no equivalent and are skipped.
  static List<String> parseGeositeDomains(Iterable<String> lines) {
    final rules = <String>[];
    final valid = RegExp(r'^[a-z0-9.-]+\.[a-z0-9-]+$');
    for (final raw in lines) {
      var line = raw.split('#').first.trim().toLowerCase();
      final attribute = line.indexOf(' @');
      if (attribute >= 0) line = line.substring(0, attribute).trim();
      if (line.isEmpty) continue;
      final (kind, value) = line.startsWith('domain:')
          ? ('domain', line.substring(7))
          : line.startsWith('full:')
          ? ('full', line.substring(5))
          : line.contains(':')
          ? ('skip', '')
          : ('domain', line);
      if (kind == 'skip' || !valid.hasMatch(value)) continue;
      rules.add(value);
      if (kind == 'domain') rules.add('*.$value');
    }

    return rules;
  }
}

class _Source {
  final String name;
  final List<String> urls;

  const _Source(this.name, this.urls);
}

/// The merged Russian networks and domains.
class RuLists {
  final List<String> v4Cidrs;
  final List<String> v6Cidrs;

  /// Engine rules: `x` and `*.x` for each domain.
  final List<String> domains;

  /// Russian app packages (community lists, quorum).
  final Set<String> apps;
  final DateTime? updatedAt;

  RuLists({
    required this.v4Cidrs,
    required this.v6Cidrs,
    required this.domains,
    this.apps = const {},
    required this.updatedAt,
  });

  int get networkCount => v4Cidrs.length + v6Cidrs.length;

  bool get isEmpty => domains.isEmpty && networkCount == 0;

  /// Every network, for engine exclusions.
  List<String> get cidrs => [...v4Cidrs, ...v6Cidrs];

  /// These lists with [addresses] cut out: only the few networks that
  /// contain one of them are recomputed.
  RuLists without(Iterable<String> addresses) => RuLists(
    v4Cidrs: cidrsWithout(v4Cidrs, addresses),
    v6Cidrs: cidrsWithout(v6Cidrs, addresses),
    domains: domains,
    apps: apps,
    updatedAt: updatedAt,
  );
}
