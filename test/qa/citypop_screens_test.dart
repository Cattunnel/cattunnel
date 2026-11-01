import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/assets/font_families.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/theme/app_theme.dart';
import 'package:trusttunnel/common/theme/theme_palette.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/widgets/citypop/city_home.dart';
import 'package:trusttunnel/widgets/citypop/city_scene.dart';
import 'package:trusttunnel/widgets/citypop/city_style.dart';

/// Screenshots of the «City pop» style, for people to look at (not goldens):
/// the home in four VPN states at day, dusk and night, plus the other screens
/// in the style's theme. Written to qa/citypop/shots/.
///
/// Honest limits: the kanji of the signs and of the status are drawn from the
/// system's Japanese font, which flutter_test does not have, so they show as
/// boxes here (kana come from the bundled font). The settings, server list,
/// diagnostics and onboarding shots are assembled from the same Material
/// widgets and strings as the real screens, because the real ones need the
/// whole dependency tree; they show the theme, not the screens' own code.
const _out = 'qa/citypop/shots';

ThemeData _theme(bool night) => CityPopTheme.apply(
  AppTheme(night ? ThemePalette.cityPopDark : ThemePalette.cityPopLight, font: FontFamilies.mPlus1p).data,
  night: night,
);

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(rootBundle.load(f));
    }
    await loader.load();
  }

  await load(FontFamilies.delaGothicOne, ['assets/fonts/citypop/DelaGothicOne-Regular.ttf']);
  await load(FontFamilies.mPlus1p, [
    'assets/fonts/citypop/MPLUS1p-Medium.ttf',
    'assets/fonts/citypop/MPLUS1p-ExtraBold.ttf',
  ]);
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icon = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icon.existsSync()) {
      final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(await icon.readAsBytes())));
      await icons.load();
    }
  }
}

Future<void> _shot(
  WidgetTester tester,
  String name,
  Widget home, {
  required double width,
  required bool night,
  double scale = 1,
}) async {
  final height = width >= 400 ? 915.0 : 800.0;
  await tester.binding.setSurfaceSize(Size(width, height));
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('shot'),
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: Localization.supportedLocales,
        localizationsDelegates: Localization.localizationDelegates,
        theme: _theme(night),
        themeAnimationDuration: Duration.zero,
        debugShowCheckedModeBanner: false,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, height),
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 28),
          ),
          child: KeyedSubtree(key: ValueKey(name), child: home),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump(const Duration(milliseconds: 400));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_out/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Widget _home(VpnState state, double tod) => Scaffold(
  backgroundColor: Colors.transparent,
  body: CityHomeBody(
    state: state,
    serverName: 'Амстердам',
    serverSub: 'Нидерланды',
    pingMs: 42,
    session: state == VpnState.connected ? const Duration(minutes: 14, seconds: 32) : null,
    onPlay: () {},
    onStop: () {},
    onPickServer: () {},
    still: 14,
    timeOfDay: tod,
  ),
);

/// Pages other than the home sit on the calm airbrush sky.
Widget _page(BuildContext context, String title, Widget body) => CityBackdrop(
  child: Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(centerTitle: true, title: CityAppBarTitle(title)),
    body: body,
  ),
);

Widget _settings() => Builder(
  builder: (context) {
    final ln = context.ln;

    return _page(
      context,
      ln.settings,
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text(ln.appearance),
                  subtitle: const Text('City pop'),
                  trailing: const Icon(Icons.chevron_right),
                ),
                SwitchListTile(
                  value: true,
                  onChanged: (_) {},
                  title: Text(ln.killSwitch),
                  subtitle: Text(ln.killSwitchDescription),
                ),
                SwitchListTile(value: false, onChanged: (_) {}, title: Text(ln.connectionNotifications)),
                ListTile(title: Text(ln.connectionLog), trailing: const Icon(Icons.chevron_right)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () {}, child: Text(ln.connect)),
        ],
      ),
    );
  },
);

Widget _serverSheet() => Builder(
  builder: (context) {
    final ln = context.ln;
    final sheet = Theme.of(context).bottomSheetTheme;

    return _page(
      context,
      ln.servers,
      Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: sheet.backgroundColor,
          shape: sheet.shape,
          shadowColor: sheet.shadowColor,
          elevation: 14,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(ln.cozyChooseServer, style: Theme.of(context).textTheme.titleLarge)),
                    TextButton(onPressed: () {}, child: Text(ln.cozyTestAll)),
                  ],
                ),
                for (final (n, ip, ms) in [
                  ('Амстердам', 'Нидерланды', 42),
                  ('Франкфурт', 'Германия', 58),
                  ('Хельсинки', 'Финляндия', 71),
                  ('Москва', 'Россия', -1),
                ])
                  ListTile(
                    selected: n == 'Амстердам',
                    title: Text(n),
                    subtitle: Text(ip),
                    trailing: Text(ms > 0 ? ln.cozyPing(ms) : ln.serverUnreachable),
                  ),
                Text(ln.cozyLongPressHint, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  },
);

Widget _diagnostics() => Builder(
  builder: (context) {
    final ln = context.ln;

    return _page(
      context,
      ln.servers,
      Center(
        child: AlertDialog(
          title: Text(ln.diagTitleDone),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Image.asset(AssetImages.catMagnifier, height: 84)),
              const SizedBox(height: 8),
              for (final (t, ok) in [(ln.diagStepInternet, true), (ln.diagStepServer, true), (ln.diagStepTls, false)])
                Row(
                  children: [
                    Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.teal : Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Text(t),
                  ],
                ),
              const SizedBox(height: 8),
              Text(ln.diagVerdictTlsBlocked, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          actions: [
            TextButton(onPressed: () {}, child: Text(ln.diagClose)),
            FilledButton(onPressed: () {}, child: Text(ln.diagRetry)),
          ],
        ),
      ),
    );
  },
);

Widget _onboarding() => Builder(
  builder: (context) {
    final ln = context.ln;

    return CityBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding: const EdgeInsets.fromLTRB(28, 80, 28, 28),
          child: Column(
            children: [
              Image.asset(AssetImages.catWave, height: 220),
              const SizedBox(height: 20),
              Text(
                ln.onboardingWelcomeTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(ln.onboardingWelcomeDescription, textAlign: TextAlign.center),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(onPressed: () {}, child: Text(ln.onboardingSkip)),
                  FilledButton(onPressed: () {}, child: Text(ln.onboardingNext)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  },
);

void main() {
  setUpAll(_loadFonts);

  testWidgets('City pop home: four states at day, dusk and night', (tester) async {
    // A shader that fails to compile loads as null and the scene falls back to
    // flat colours, while every screenshot still gets written. Fail loudly.
    expect(await tester.runAsync(cityShaderLoads), isTrue, reason: 'shaders/city.frag did not compile');
    final states = {
      'off': VpnState.disconnected,
      'connecting': VpnState.connecting,
      'on': VpnState.connected,
      'error': VpnState.waitingForRecovery,
    };
    final times = {'day': 0.0, 'dusk': 0.5, 'night': 1.0};
    for (final width in [360.0, 412.0]) {
      for (final MapEntry(key: sName, value: state) in states.entries) {
        for (final MapEntry(key: tName, value: tod) in times.entries) {
          await _shot(
            tester,
            'home_${sName}_${tName}_${width.toInt()}',
            _home(state, tod),
            width: width,
            night: tod >= 1,
          );
        }
      }
    }
    await tester.binding.setSurfaceSize(null);
    expect(tester.takeException(), isNull);
  });

  testWidgets('City pop other screens: settings, servers, diagnostics, onboarding', (tester) async {
    for (final width in [360.0, 412.0]) {
      for (final night in [false, true]) {
        final suffix = '${night ? 'night' : 'dusk'}_${width.toInt()}';
        await _shot(tester, 'settings_$suffix', _settings(), width: width, night: night);
        await _shot(tester, 'servers_$suffix', _serverSheet(), width: width, night: night);
        await _shot(tester, 'diag_$suffix', _diagnostics(), width: width, night: night);
        await _shot(tester, 'onboarding_$suffix', _onboarding(), width: width, night: night);
      }
    }
    await tester.binding.setSurfaceSize(null);
    expect(tester.takeException(), isNull);
  });
}
