import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/theme/app_theme.dart';
import 'package:trusttunnel/common/theme/theme_palette.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/vpn_protocol.dart';
import 'package:trusttunnel/feature/vpn/domain/anti_dpi_auto.dart';
import 'package:trusttunnel/feature/vpn/domain/connection_diagnostics.dart';
import 'package:trusttunnel/feature/vpn/widgets/anti_dpi_status_line.dart';
import 'package:trusttunnel/feature/vpn/widgets/connection_diagnosis_dialog.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';
import 'package:vpn_plugin/models/net_diagnostic.dart';

/// Screenshots for the "first users" check: Marsik's diagnosis dialog and
/// the anti-DPI status line in every state and both languages.
///
/// The images are written next to the report, not compared as goldens:
/// golden files depend on the renderer, and these are for people to look at.
const _out = 'qa/first-users/round1';
final _errors = StringBuffer();

Server _server(String name) => Server(
  id: 'qa-server',
  serverData: ServerData(
    name: name,
    ipAddress: '203.0.113.9:443',
    domain: 'vpn.example.org',
    username: 'u',
    password: 'p',
    vpnProtocol: VpnProtocol.http2,
    dnsServers: const [],
    routingProfileId: 'default',
    ipv6: false,
  ),
);

Map<DiagnosisStep, DiagnosisStepStatus> _steps({
  DiagnosisStepStatus internet = DiagnosisStepStatus.ok,
  DiagnosisStepStatus server = DiagnosisStepStatus.ok,
  DiagnosisStepStatus tls = DiagnosisStepStatus.ok,
  DiagnosisStepStatus access = DiagnosisStepStatus.ok,
}) => {
  DiagnosisStep.internet: internet,
  DiagnosisStep.server: server,
  DiagnosisStep.tls: tls,
  DiagnosisStep.access: access,
};

Map<DiagnosisStep, DiagnosisStepStatus> _verdictSteps(DiagnosisVerdict verdict) => switch (verdict) {
  DiagnosisVerdict.noInternet || DiagnosisVerdict.captivePortal => _steps(
    internet: DiagnosisStepStatus.failed,
    server: DiagnosisStepStatus.skipped,
    tls: DiagnosisStepStatus.skipped,
    access: DiagnosisStepStatus.skipped,
  ),
  DiagnosisVerdict.networkCuts || DiagnosisVerdict.bypassNeeded || DiagnosisVerdict.addressFrozen => _steps(
    server: DiagnosisStepStatus.skipped,
    tls: DiagnosisStepStatus.skipped,
    access: DiagnosisStepStatus.skipped,
  ),
  DiagnosisVerdict.serverTimeout || DiagnosisVerdict.serverRefused => _steps(
    server: DiagnosisStepStatus.failed,
    tls: DiagnosisStepStatus.skipped,
    access: DiagnosisStepStatus.skipped,
  ),
  DiagnosisVerdict.sniBlocked || DiagnosisVerdict.tlsBlocked => _steps(
    tls: DiagnosisStepStatus.failed,
    access: DiagnosisStepStatus.skipped,
  ),
  DiagnosisVerdict.keysUpdated => _steps(),
  DiagnosisVerdict.accessEnded || DiagnosisVerdict.keysRejected || DiagnosisVerdict.inconclusive => _steps(
    access: DiagnosisStepStatus.failed,
  ),
  DiagnosisVerdict.trafficBlocked => _steps(),
  DiagnosisVerdict.clockWrong => _steps(
    server: DiagnosisStepStatus.skipped,
    tls: DiagnosisStepStatus.skipped,
    access: DiagnosisStepStatus.skipped,
  ),
};

ConnectionDiagnosis _diagnosis(DiagnosisVerdict verdict, {Server? alternative}) => ConnectionDiagnosis(
  verdict: verdict,
  alternative: alternative,
  engine: verdict == DiagnosisVerdict.networkCuts
      ? NetDiagnostic.parse('symptom=cut_after_bytes proto=h2 up=1 down=2 dur_ms=10 idle_ms=5 repeat=2 cut=16342')
      : null,
);

ThemeData _theme(bool dark) => AppTheme(dark ? ThemePalette.dark : ThemePalette.light).data;

Widget _app({
  required Widget child,
  required String locale,
  required bool dark,
  required double width,
  required double height,
  double scale = 1,
}) => MaterialApp(
  locale: Locale(locale),
  supportedLocales: Localization.supportedLocales,
  localizationsDelegates: Localization.localizationDelegates,
  theme: _theme(dark),
  themeAnimationDuration: Duration.zero,
  debugShowCheckedModeBanner: false,
  home: MediaQuery(
    data: MediaQueryData(size: Size(width, height), textScaler: TextScaler.linear(scale)),
    child: Scaffold(backgroundColor: _theme(dark).colorScheme.surface, body: child),
  ),
);

Widget _status(AntiDpiStatus? status) {
  VpnScope.antiDpiStatus.value = status;

  return const Center(
    child: Padding(padding: EdgeInsets.all(24), child: AntiDpiStatusLine()),
  );
}

ConnectionDiagnosisDialog _dialog({
  required String locale,
  required Server server,
  ConnectionDiagnosis? diagnosis,
  Map<DiagnosisStep, DiagnosisStepStatus>? steps,
  String? networkName,
  bool connected = false,
  bool skip = false,
}) => ConnectionDiagnosisDialog(
  server: server,
  otherServers: const [],
  debugDiagnosis: diagnosis,
  debugSteps: steps,
  debugNetworkName: networkName,
  debugConnectedMeanwhile: connected,
  debugSkipDiagnostics: skip,
);

Future<void> _save(WidgetTester tester, String name) async {
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

Future<void> _shot(
  WidgetTester tester,
  String name, {
  required Widget child,
  required String locale,
  required bool dark,
  required double width,
  double height = 900,
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, height));
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('shot'),
      child: _app(
        locale: locale,
        dark: dark,
        width: width,
        height: height,
        scale: scale,
        child: KeyedSubtree(key: ValueKey(name), child: child),
      ),
    ),
  );
  await tester.pump();
  // Let the asset images decode before the frame is captured.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  Object? error;
  while ((error = tester.takeException()) != null) {
    _errors.writeln('$name: $error');
  }
  await _save(tester, name);
}

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final loaders = <String, List<String>>{
    'Roboto': [
      'assets/fonts/roboto/Roboto-Regular.ttf',
      'assets/fonts/roboto/Roboto-Medium.ttf',
      'assets/fonts/roboto/Roboto-Bold.ttf',
    ],
  };
  for (final entry in loaders.entries) {
    final loader = FontLoader(entry.key);
    for (final asset in entry.value) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }
  if (root != null) {
    final icon = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icon.existsSync()) {
      final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(await icon.readAsBytes())));
      await loader.load();
    }
  }
}

void main() {
  setUpAll(_loadFonts);

  tearDown(() {
    VpnScope.antiDpiStatus.value = null;
  });

  testWidgets('dialog: every verdict, both languages, widths and themes', (tester) async {
    const locales = ['ru', 'en'];
    const widths = [360.0, 412.0];
    const themes = [false, true];

    for (final locale in locales) {
      final server = _server(locale == 'ru' ? 'Германия 1' : 'Germany 1');
      final alternative = _server(locale == 'ru' ? 'Нидерланды' : 'Netherlands');
      for (final width in widths) {
        for (final dark in themes) {
          for (final verdict in DiagnosisVerdict.values) {
            for (final withAlternative in [false, true]) {
              final tail = '${locale}_w${width.toInt()}_${dark ? 'dark' : 'light'}_alt${withAlternative ? 1 : 0}';
              await _shot(
                tester,
                'dialog_${verdict.name}_$tail',
                locale: locale,
                dark: dark,
                width: width,
                child: _dialog(
                  locale: locale,
                  server: server,
                  diagnosis: _diagnosis(verdict, alternative: withAlternative ? alternative : null),
                  steps: _verdictSteps(verdict),
                  networkName: locale == 'ru' ? 'Домашний Wi-Fi' : 'Home Wi-Fi',
                ),
              );
            }
          }
        }
      }
    }
  });

  testWidgets('dialog: large font, width 412', (tester) async {
    for (final locale in ['ru', 'en']) {
      final server = _server(locale == 'ru' ? 'Германия 1' : 'Germany 1');
      for (final dark in [false, true]) {
        for (final verdict in DiagnosisVerdict.values) {
          await _shot(
            tester,
            'dialog_large_${verdict.name}_${locale}_${dark ? 'dark' : 'light'}',
            locale: locale,
            dark: dark,
            width: 412,
            scale: 1.3,
            height: 1100,
            child: _dialog(
              locale: locale,
              server: server,
              diagnosis: _diagnosis(verdict),
              steps: _verdictSteps(verdict),
              networkName: locale == 'ru' ? 'Домашний Wi-Fi' : 'Home Wi-Fi',
            ),
          );
        }
      }
    }
  });

  testWidgets('dialog: round is running, failed, worked, connected meanwhile', (tester) async {
    const locales = ['ru', 'en'];
    const widths = [360.0, 412.0];
    const themes = [false, true];
    final running = _steps(
      server: DiagnosisStepStatus.running,
      tls: DiagnosisStepStatus.pending,
      access: DiagnosisStepStatus.pending,
    );

    for (final locale in locales) {
      final server = _server(locale == 'ru' ? 'Германия 1' : 'Germany 1');
      final round = AntiDpiRound(
        serverId: server.id,
        network: 'wifi',
        kind: 'wifi',
        triedPlain: true,
        triedModes: const [1, 2],
        workedMode: null,
        pathCut: true,
        at: DateTime.now(),
      );
      for (final width in widths) {
        for (final dark in themes) {
          final tail = '${locale}_w${width.toInt()}_${dark ? 'dark' : 'light'}';
          await _shot(
            tester,
            'dialog_round_running_$tail',
            locale: locale,
            dark: dark,
            width: width,
            child: _dialog(
              locale: locale,
              server: server,
              steps: running,
              networkName: locale == 'ru' ? 'Домашний Wi-Fi' : 'Home Wi-Fi',
              skip: true,
            ),
          );
          await _shot(
            tester,
            'dialog_round_failed_$tail',
            locale: locale,
            dark: dark,
            width: width,
            child: _dialog(
              locale: locale,
              server: server,
              diagnosis: ConnectionDiagnosis(verdict: DiagnosisVerdict.networkCuts, auto: round),
              steps: _steps(
                server: DiagnosisStepStatus.skipped,
                tls: DiagnosisStepStatus.skipped,
                access: DiagnosisStepStatus.skipped,
              ),
              networkName: locale == 'ru' ? 'Домашний Wi-Fi' : 'Home Wi-Fi',
            ),
          );
          await _shot(
            tester,
            'dialog_round_worked_$tail',
            locale: locale,
            dark: dark,
            width: width,
            child: _dialog(
              locale: locale,
              server: server,
              connected: true,
              steps: _steps(),
              networkName: locale == 'ru' ? 'Домашний Wi-Fi' : 'Home Wi-Fi',
              skip: true,
            ),
          );
        }
      }
    }
  });

  testWidgets('status line: every step and phrasing', (tester) async {
    const locales = ['ru', 'en'];
    const widths = [360.0, 412.0];
    const themes = [false, true];
    final states = <String, AntiDpiStatus>{
      'direct': const AntiDpiStatus(step: AntiDpiStep.tryingDirect, networkName: 'Wi-Fi'),
      'cut': const AntiDpiStatus(step: AntiDpiStep.cut, networkName: 'Wi-Fi'),
      'technique_2': const AntiDpiStatus(
        step: AntiDpiStep.tryingTechnique,
        index: 1,
        total: 2,
        mode: 1,
        networkName: 'Wi-Fi',
      ),
      'technique_single': const AntiDpiStatus(
        step: AntiDpiStep.tryingTechnique,
        index: 1,
        total: 1,
        mode: 1,
        networkName: 'Wi-Fi',
      ),
      'worked_bypass': const AntiDpiStatus(
        step: AntiDpiStep.worked,
        mode: 1,
        networkName: 'МТС',
      ),
      'worked_plain': const AntiDpiStatus(
        step: AntiDpiStep.worked,
        networkName: 'Домашний Wi-Fi',
        plainWorked: true,
      ),
      'failed_plain': const AntiDpiStatus(
        step: AntiDpiStep.failed,
        bypassTried: 2,
        triedPlain: true,
        networkName: 'МТС',
      ),
      'failed_modes': const AntiDpiStatus(
        step: AntiDpiStep.failed,
        bypassTried: 5,
        networkName: 'МТС',
      ),
    };

    for (final locale in locales) {
      for (final width in widths) {
        for (final dark in themes) {
          for (final entry in states.entries) {
            await _shot(
              tester,
              'status_${entry.key}_${locale}_w${width.toInt()}_${dark ? 'dark' : 'light'}',
              locale: locale,
              dark: dark,
              width: width,
              height: 160,
              child: _status(entry.value),
            );
          }
        }
      }
    }
  });

  testWidgets('dialog and status line in one frame', (tester) async {
    const locales = ['ru', 'en'];
    for (final locale in locales) {
      final server = _server(locale == 'ru' ? 'Германия 1' : 'Germany 1');
      final wifi = locale == 'ru' ? 'Домашний Wi-Fi' : 'Home Wi-Fi';
      for (final dark in [false, true]) {
        final tail = '${locale}_420_${dark ? 'dark' : 'light'}';
        Future<void> pair(String name, Widget status, ConnectionDiagnosisDialog dialog) => _shot(
          tester,
          'pair_${name}_$tail',
          locale: locale,
          dark: dark,
          width: 420,
          height: 1400,
          scale: 1.3,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(padding: const EdgeInsets.only(top: 24, left: 16, right: 16), child: status),
                dialog,
              ],
            ),
          ),
        );

        await pair(
          'wifi_with_mobile_data',
          _status(AntiDpiStatus(step: AntiDpiStep.worked, mode: 1, networkName: wifi)),
          _dialog(
            locale: locale,
            server: server,
            diagnosis: _diagnosis(DiagnosisVerdict.bypassNeeded),
            steps: _verdictSteps(DiagnosisVerdict.bypassNeeded),
            networkName: wifi,
          ),
        );
        await pair(
          'round_failed',
          _status(const AntiDpiStatus(step: AntiDpiStep.failed, bypassTried: 2, triedPlain: true, networkName: 'МТС')),
          _dialog(
            locale: locale,
            server: server,
            diagnosis: ConnectionDiagnosis(
              verdict: DiagnosisVerdict.networkCuts,
              auto: AntiDpiRound(
                serverId: server.id,
                network: 'mobile:25001',
                kind: 'mobile',
                triedPlain: true,
                triedModes: const [1, 2],
                workedMode: null,
                pathCut: true,
                at: DateTime.now(),
              ),
            ),
            steps: _verdictSteps(DiagnosisVerdict.networkCuts),
            networkName: locale == 'ru' ? 'МТС' : 'MTS',
          ),
        );
        await pair(
          'contradiction_no_internet',
          _status(const AntiDpiStatus(step: AntiDpiStep.tryingDirect, networkName: 'МТС')),
          _dialog(
            locale: locale,
            server: server,
            diagnosis: _diagnosis(DiagnosisVerdict.noInternet),
            steps: _verdictSteps(DiagnosisVerdict.noInternet),
            networkName: locale == 'ru' ? 'МТС' : 'MTS',
          ),
        );
      }
    }
  });

  tearDownAll(() {
    final file = File('$_out/errors.txt');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(_errors.isEmpty ? 'no overflow\n' : _errors.toString());
  });
}
