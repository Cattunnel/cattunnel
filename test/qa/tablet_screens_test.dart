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
import 'package:trusttunnel/feature/server/servers/widget/cozy/cozy_servers_view.dart';
import 'package:trusttunnel/widgets/aero/aero_widgets.dart';

const _out = 'qa/tablet';

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

Future<void> _loadFonts() async {
  final loader = FontLoader(FontFamilies.nunito);
  for (final weight in ['Regular', 'SemiBold', 'Bold', 'ExtraBold', 'Black']) {
    loader.addFont(rootBundle.load('assets/fonts/aero/Nunito-$weight.ttf'));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('tablet: Aero server card at tablet widths', (tester) async {
    const widths = [600.0, 800.0, 960.0, 1280.0];
    const heights = [960.0, 1280.0, 600.0, 800.0];
    const scales = [1.0, 1.3];
    final errors = StringBuffer();

    for (var i = 0; i < widths.length; i++) {
      final width = widths[i];
      final height = heights[i];
      for (final scale in scales) {
        final shot = 'card_w${width.toInt()}_h${height.toInt()}_x$scale';
        await tester.binding.setSurfaceSize(Size(width, height));
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('shot'),
            child: MaterialApp(
              locale: const Locale('ru'),
              supportedLocales: Localization.supportedLocales,
              localizationsDelegates: Localization.localizationDelegates,
              theme: _theme(false),
              themeAnimationDuration: Duration.zero,
              debugShowCheckedModeBanner: false,
              home: MediaQuery(
                data: MediaQueryData(size: Size(width, height), textScaler: TextScaler.linear(scale)),
                child: KeyedSubtree(
                  key: ValueKey(shot),
                  child: Scaffold(
                    body: Center(
                      child: AeroServerCardView(
                        server: _server('Нидерланды, Амстердам, резервный сервер подписки'),
                        latency: const Duration(milliseconds: 87),
                        onTap: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 300));
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
    await tester.binding.setSurfaceSize(null);
    expect(errors.toString(), isEmpty);
  });
}
