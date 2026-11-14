import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/theme/app_theme.dart';
import 'package:trusttunnel/common/theme/theme_palette.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/feature/vpn/domain/connection_diagnostics.dart';
import 'package:trusttunnel/feature/vpn/widgets/connection_diagnosis_dialog.dart';

void main() {
  testWidgets('Back with a diagnosis dialog followed by background/resume preserves home', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: AppTheme(ThemePalette.light).data,
        localizationsDelegates: Localization.localizationDelegates,
        supportedLocales: Localization.supportedLocales,
        home: const Scaffold(body: Text('Home remains')),
      ),
    );
    await tester.pumpAndSettle();
    final closed = showDialog<void>(
      context: navigator.currentContext!,
      barrierDismissible: false,
      barrierColor: Colors.black45,
      builder: (_) => ConnectionDiagnosisDialog(
        server: Server(
          id: 'fictional',
          serverData: const ServerData.empty(name: 'Fictional'),
        ),
        otherServers: const [],
        debugDiagnosis: const ConnectionDiagnosis(verdict: DiagnosisVerdict.inconclusive),
        debugAttemptRunning: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionDiagnosisDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await closed;
    expect(find.byType(ConnectionDiagnosisDialog), findsNothing);
    expect(find.text('Home remains'), findsOneWidget);
    expect(navigator.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });
}
