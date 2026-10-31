import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/theme/app_theme.dart';
import 'package:trusttunnel/common/theme/theme_palette.dart';
import 'package:trusttunnel/feature/vpn/domain/connection_diagnostics.dart';
import 'package:trusttunnel/feature/vpn/domain/connection_doctor.dart';
import 'package:trusttunnel/feature/vpn/widgets/anti_dpi_status_line.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';

void main() {
  group('alternativeHelps', () {
    test('another server only where the trouble is on the way to this one', () {
      final helps = DiagnosisVerdict.values.where(ConnectionDoctor.alternativeHelps).toSet();

      expect(helps, {
        DiagnosisVerdict.networkCuts,
        DiagnosisVerdict.serverTimeout,
        DiagnosisVerdict.serverRefused,
        DiagnosisVerdict.tlsBlocked,
        DiagnosisVerdict.trafficBlocked,
        DiagnosisVerdict.addressFrozen,
      });
    });
  });

  group('actionFor', () {
    test('every verdict but the frozen address and the new keys has a button', () {
      for (final verdict in DiagnosisVerdict.values) {
        final action = ConnectionDoctor.actionFor(verdict, systemSettings: true);
        final expectNone = verdict == DiagnosisVerdict.addressFrozen || verdict == DiagnosisVerdict.keysUpdated;
        expect(action == DoctorAction.none, expectNone, reason: verdict.name);
      }
    });

    test('system screens only where the platform has them', () {
      expect(
        ConnectionDoctor.actionFor(DiagnosisVerdict.captivePortal, systemSettings: true),
        DoctorAction.wifiSettings,
      );
      expect(ConnectionDoctor.actionFor(DiagnosisVerdict.clockWrong, systemSettings: true), DoctorAction.dateSettings);
      expect(ConnectionDoctor.actionFor(DiagnosisVerdict.captivePortal, systemSettings: false), DoctorAction.retry);
      expect(ConnectionDoctor.actionFor(DiagnosisVerdict.clockWrong, systemSettings: false), DoctorAction.retry);
    });

    test('a refused key or an ended subscription goes to the admin', () {
      for (final verdict in [DiagnosisVerdict.keysRejected, DiagnosisVerdict.accessEnded]) {
        expect(ConnectionDoctor.actionFor(verdict, systemSettings: true), DoctorAction.messageAdmin);
      }
    });
  });

  testWidgets('the line under the button is quiet while Marsik speaks', (tester) async {
    addTearDown(() {
      VpnScope.antiDpiStatus.value = null;
      ConnectionDoctor.marsikOpen.value = false;
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        theme: AppTheme(ThemePalette.light).data,
        supportedLocales: Localization.supportedLocales,
        localizationsDelegates: Localization.localizationDelegates,
        home: const Scaffold(body: AntiDpiStatusLine()),
      ),
    );
    VpnScope.antiDpiStatus.value = const AntiDpiStatus(step: AntiDpiStep.tryingDirect);
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsOneWidget);

    ConnectionDoctor.marsikOpen.value = true;
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNothing);

    ConnectionDoctor.marsikOpen.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsOneWidget);
  });
}
