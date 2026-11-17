import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';
import 'package:trusttunnel/data/database/app_database.dart';
import 'package:trusttunnel/data/datasources/local_sources/server_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/local_sources/subscription_datasource_impl.dart';
import 'package:trusttunnel/data/domain/subscription_poll_log.dart';
import 'package:trusttunnel/data/domain/subscription_sync_service.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/data/model/subscription_poll.dart';
import 'package:vpn_plugin/deep_link_manager.dart';

void main() {
  setUpAll(() {
    if (Platform.isLinux) {
      open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
    }
  });

  test('a timeout on the first mirror and 200 on the second give two records in order', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.inMemory(NativeDatabase.memory());
    addTearDown(db.close);

    final source = SubscriptionDataSourceImpl(database: db);
    final subscription = await source.addSubscription(
      request: const SubscriptionData(
        name: 'Test',
        url: 'https://first.example:8443/api/ct/fictional-token | https://second.example/api/ct/fictional-token',
      ),
    );
    final serverSource = ServerDataSourceImpl(database: db, deepLinkManager: DeepLinkManagerImpl());
    final pollLog = SubscriptionPollLog(preferences: prefs);
    final sync = SubscriptionSyncService(
      subscriptionDataSource: source,
      serverDataSource: serverSource,
      pollLog: pollLog,
    );
    final fixture = jsonDecode(File('test/fixtures/bot_subscription_links.json').readAsStringSync()) as Map;

    await http.runWithClient(
      () => sync.refresh(subscription),
      () => MockClient((request) async {
        if (request.url.host == 'first.example') {
          throw TimeoutException('no answer');
        }

        return http.Response(fixture['on'] as String, 200);
      }),
    );

    final poll = pollLog.pollOf(subscription.id!)!;
    expect(poll.succeeded, isTrue);
    expect(poll.finishedAt, isNotNull);
    expect(poll.currentHost, isNull);
    expect(poll.attempts.map((attempt) => attempt.host), ['first.example:8443', 'second.example']);
    expect(poll.attempts.map((attempt) => attempt.outcome), [
      SubscriptionPollOutcome.timeout,
      SubscriptionPollOutcome.ok,
    ]);
    expect(poll.attempts.last.statusCode, 200);

    // The whole record (screen and exported log) must not carry the token.
    final dump = '${poll.toJson()} ${poll.toJsonString()} ${pollLog.toLogLines().join('\n')}';
    expect(dump, isNot(contains('fictional-token')));
    expect(dump, isNot(contains('/api/ct')));
  });

  test('the poll survives a restart and the failed one replaces the old result', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.inMemory(NativeDatabase.memory());
    addTearDown(db.close);

    final source = SubscriptionDataSourceImpl(database: db);
    final subscription = await source.addSubscription(
      request: const SubscriptionData(name: 'Test', url: 'https://only.example/api/ct/fictional-token'),
    );
    final serverSource = ServerDataSourceImpl(database: db, deepLinkManager: DeepLinkManagerImpl());
    final pollLog = SubscriptionPollLog(preferences: prefs);
    final sync = SubscriptionSyncService(
      subscriptionDataSource: source,
      serverDataSource: serverSource,
      pollLog: pollLog,
    );
    final fixture = jsonDecode(File('test/fixtures/bot_subscription_links.json').readAsStringSync()) as Map;

    await http.runWithClient(
      () => sync.refresh(subscription),
      () => MockClient((_) async => http.Response(fixture['on'] as String, 200)),
    );

    final reloaded = SubscriptionPollLog(preferences: prefs).pollOf(subscription.id!)!;
    expect(reloaded.succeeded, isTrue);
    expect(reloaded.attempts.single.host, 'only.example');
    expect(reloaded.attempts.single.outcome, SubscriptionPollOutcome.ok);

    await http.runWithClient(
      () => expectLater(sync.refresh(subscription), throwsA(isA<SubscriptionFetchException>())),
      () => MockClient((_) async => http.Response('gone', 404)),
    );

    final failed = pollLog.pollOf(subscription.id!)!;
    expect(failed.succeeded, isFalse);
    expect(failed.attempts.single.outcome, SubscriptionPollOutcome.http);
    expect(failed.attempts.single.statusCode, 404);
  });
}
