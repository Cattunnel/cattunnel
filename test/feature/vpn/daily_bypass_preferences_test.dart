import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/feature/vpn/domain/anti_dpi_auto.dart';
import 'package:trusttunnel/feature/vpn/domain/daily_bypass_preferences.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/subscription_override_dialog.dart';

void main() {
  test('manual permission expires at local midnight; key setting has precedence', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const data = ServerData.empty();
    final now = DateTime(2026, 11, 14, 23, 59);
    expect(DailyBypassPreferences.automaticFor(data, prefs, now: now), isFalse);
    await DailyBypassPreferences.setEnabled(prefs, true, now: now);
    expect(DailyBypassPreferences.automaticFor(data, prefs, now: now), isTrue);
    expect(DailyBypassPreferences.automaticFor(data, prefs, now: DateTime(2026, 11, 15)), isFalse);
    expect(DailyBypassPreferences.automaticFor(data.copyWith(subscriptionOverride: true), prefs, now: now), isFalse);
    expect(DailyBypassPreferences.automaticFor(data.copyWith(antiDpi: true, antiDpiMode: 1), prefs, now: now), isFalse);
    expect(
      DailyBypassPreferences.automaticFor(
        data.copyWith(antiDpi: true, antiDpiMode: 4),
        prefs,
        now: DateTime(2026, 11, 15),
      ),
      isTrue,
    );
  });
  test('migration removes legacy direct marks once and preserves server hints', () async {
    SharedPreferences.setMockInitialValues({
      'anti_dpi_direct.7.net': 123,
      'anti_dpi_direct_since.7.net': 123,
      'anti_dpi_auto.7.net': 2,
      'anti_dpi_sub.7.net': 3,
    });
    final prefs = await SharedPreferences.getInstance();
    final auto = AntiDpiAuto(prefs);
    await auto.migrateLegacyDirectMemory();
    expect(prefs.containsKey('anti_dpi_direct.7.net'), isFalse);
    expect(prefs.containsKey('anti_dpi_direct_since.7.net'), isFalse);
    expect(prefs.getInt('anti_dpi_auto.7.net'), 2);
    expect(prefs.getInt('anti_dpi_sub.7.net'), 3);
    await auto.rememberDirectFailure(serverId: '7', network: 'net');
    await auto.migrateLegacyDirectMemory();
    expect(auto.directFails(serverId: '7', network: 'net'), isTrue);
  });
  test('unsuccessful bypass is remembered only for that server/network/day', () async {
    SharedPreferences.setMockInitialValues({});
    final auto = AntiDpiAuto(await SharedPreferences.getInstance());
    final now = DateTime(2026, 11, 14, 23, 59);
    await auto.rememberFailed(serverId: '7', network: 'net', now: now);
    expect(auto.directFails(serverId: '7', network: 'net', now: now), isFalse);
    expect(auto.failedToday(serverId: '7', network: 'net', now: now), isTrue);
    expect(auto.failedToday(serverId: '8', network: 'net', now: now), isFalse);
    expect(auto.failedToday(serverId: '7', network: 'other', now: now), isFalse);
    expect(auto.failedToday(serverId: '7', network: 'net', now: DateTime(2026, 11, 15)), isFalse);
  });
  test('challenge normalization and retry always changes the question', () {
    for (final text in ['SYN-ACK', 'syn ack', ' Syn - Ack ']) {
      expect(SubscriptionChallenge.accepts(0, text), isTrue);
    }
    for (final text in ['ClientHello', 'Client Hello', 'client-hello']) {
      expect(SubscriptionChallenge.accepts(7, text), isTrue);
    }
    expect(SubscriptionChallenge.accepts(0, 'ack'), isFalse);
    final random = Random(42);
    for (var question = 0; question < 8; question++) {
      for (var trial = 0; trial < 50; trial++) {
        expect(SubscriptionChallenge.next(question, random), isNot(question));
      }
    }
  });
}
