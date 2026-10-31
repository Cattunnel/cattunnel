import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/assets/font_families.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/theme/aero_theme.dart';
import 'package:trusttunnel/common/theme/app_theme.dart';
import 'package:trusttunnel/common/theme/theme_palette.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/vpn_protocol.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/feature/server/servers/widget/cozy/cozy_servers_view.dart';
import 'package:trusttunnel/widgets/aero/aero_widgets.dart';

/// Screenshots of the Aero home screen on a phone: the connect button and
/// the server card at the widths people have (360 dp, a Pixel 9 Pro at
/// 427 dp, a wide phone at 448 dp) and with a large font. Written for
/// people to look at, not compared as goldens. Any layout overflow fails.
const _out = 'qa/aero-home';

Server _server(String name) => Server(
  id: 'qa-$name',
  serverData: ServerData(
    name: name,
    ipAddress: 'vpn.example.org:443',
    domain: 'vpn.example.org',
    username: 'u',
    password: 'p',
    vpnProtocol: VpnProtocol.http2,
    dnsServers: const [],
    routingProfileId: 'default',
    ipv6: false,
  ),
);

ThemeData _theme(bool night) => AeroTheme.apply(
  AppTheme(night ? ThemePalette.aeroDark : ThemePalette.aeroLight, font: FontFamilies.nunito).data,
  night: night,
);

Widget _home({required Server server, required double width}) => Builder(
  builder: (context) => DecoratedBox(
    // A plain sky instead of AeroBackdrop: the backdrop listens to the
    // phone's tilt sensor, which a test does not have.
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF2F86E8), Color(0xFFBFE6FF), Color(0xFF7CC943)],
      ),
    ),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        Center(
          child: AeroConnectButton(
            state: VpnState.disconnected,
            label: context.ln.connect,
            // As CozyServersView does for Aero.
            size: CozyServersView.mobileButtonSize(width) * 0.9,
            onTap: () {},
          ),
        ),
        const SizedBox(height: 32),
        AeroServerCardView(server: server, latency: const Duration(milliseconds: 87), onTap: () {}),
      ],
    ),
  ),
);

Future<void> _loadFonts() async {
  final loader = FontLoader(FontFamilies.nunito);
  for (final weight in ['Regular', 'SemiBold', 'Bold', 'ExtraBold', 'Black']) {
    loader.addFont(rootBundle.load('assets/fonts/aero/Nunito-$weight.ttf'));
  }
  await loader.load();
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icon = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icon.existsSync()) {
      final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(await icon.readAsBytes())));
      await icons.load();
    }
  }
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('Aero home: button and server card at phone widths', (tester) async {
    const widths = [360.0, 427.0, 448.0];
    const scales = [1.0, 1.3];
    final names = ['🇩🇪 Германия', 'Нидерланды, Амстердам, резервный сервер подписки'];
    final errors = StringBuffer();
    const height = 820.0;

    for (final width in widths) {
      for (final scale in scales) {
        for (final night in [false, true]) {
          for (final (index, name) in names.indexed) {
            final shot = 'home_w${width.toInt()}_x$scale${night ? '_night' : ''}_name$index';
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
                    data: MediaQueryData(size: Size(width, height), textScaler: TextScaler.linear(scale)),
                    child: KeyedSubtree(key: ValueKey(shot), child: _home(server: _server(name), width: width)),
                  ),
                ),
              ),
            );
            await tester.pump();
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
            await tester.pump(const Duration(milliseconds: 600));
            Object? error;
            while ((error = tester.takeException()) != null) {
              errors.writeln('$shot: $error');
            }
            final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 2);
              final data = await image.toByteData(format: ui.ImageByteFormat.png);
              final file = File('$_out/$shot.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
      }
    }
    await tester.binding.setSurfaceSize(null);

    expect(errors.toString(), isEmpty);
  });
}
