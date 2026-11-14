import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value, Migrator;
import 'package:trusttunnel/data/domain/subscription_sync_service.dart';
import 'package:trusttunnel/data/datasources/local_sources/server_datasource_impl.dart';
import 'package:vpn_plugin/deep_link_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqlite3/open.dart';
import 'package:trusttunnel/data/database/app_database.dart';
import 'package:trusttunnel/data/datasources/local_sources/subscription_datasource_impl.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';

class _NoDeviceIdentityPaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => throw UnsupportedError('No device identity in this test');
}

void main() {
  setUpAll(() {
    if (Platform.isLinux) {
      open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
    }
  });
  test('subscription clears enabled anti-DPI and other transport settings', () async {
    final db = AppDatabase.inMemory(NativeDatabase.memory());
    addTearDown(db.close);
    final source = SubscriptionDataSourceImpl(database: db);
    final sub = await source.addSubscription(
      request: const SubscriptionData(
        name: 'Test',
        url: 'https://example.org/api/ct/fictional-token',
      ),
    );
    const on = ServerData.empty(
      name: 'Test server',
      antiDpi: true,
      antiDpiMode: 4,
      tlsProfile: 'chrome',
      antiDpiDesync: '1',
      h2PaddingFrames: 4,
      blockQuic: true,
    );
    await source.syncServersForSubscription(id: sub.id!, servers: [on]);
    await source.syncServersForSubscription(
      id: sub.id!,
      servers: [const ServerData.empty(name: 'Test server')],
    );
    final row = await db.select(db.servers).getSingle();
    expect(row.antiDpi, isFalse);
    expect(row.antiDpiMode, 0);
    expect(row.tlsProfile, '');
    expect(row.antiDpiDesync, '');
    expect(row.h2PaddingFrames, 0);
    expect(row.blockQuic, isFalse);
  });
  test('override protects exactly one key including credentials, DNS and deletion', () async {
    final db = AppDatabase.inMemory(NativeDatabase.memory());
    addTearDown(db.close);
    final source = SubscriptionDataSourceImpl(database: db);
    final sub = await source.addSubscription(
      request: const SubscriptionData(name: 'Test', url: 'https://example.org/api/ct/fictional-token'),
    );
    const original = ServerData.empty(
      name: 'Protected',
      username: 'manual',
      password: 'manual-pass',
      dnsServers: ['192.0.2.53'],
      antiDpi: true,
    );
    await source.syncServersForSubscription(
      id: sub.id!,
      servers: [
        original,
        original.copyWith(name: 'Managed'),
      ],
    );
    final protected = await (db.select(db.servers)..where((s) => s.name.equals('Protected'))).getSingle();
    await (db.update(
      db.servers,
    )..where((s) => s.id.equals(protected.id))).write(const ServersCompanion(subscriptionOverride: Value(true)));
    const incoming = ServerData.empty(
      name: 'Protected',
      username: 'server',
      password: 'server-pass',
      dnsServers: ['192.0.2.54'],
    );
    await source.syncServersForSubscription(
      id: sub.id!,
      servers: [
        incoming,
        incoming.copyWith(name: 'Managed'),
      ],
    );
    final serverSource = ServerDataSourceImpl(database: db, deepLinkManager: DeepLinkManagerImpl());
    final kept = await serverSource.getServerById(id: protected.id.toString());
    expect(kept.serverData.username, 'manual');
    expect(kept.serverData.password, 'manual-pass');
    expect(kept.serverData.dnsServers, ['192.0.2.53']);
    expect(kept.serverData.antiDpi, isTrue);
    expect(kept.serverData.subscriptionOverride, isTrue);
    expect(kept.serverData.copyWith(antiDpi: false).subscriptionOverride, isTrue);
    final managed = await (db.select(db.servers)..where((s) => s.name.equals('Managed'))).getSingle();
    expect(managed.login, 'server');
    expect(managed.antiDpi, isFalse);
    await source.syncServersForSubscription(id: sub.id!, servers: []);
    expect((await db.select(db.servers).get()).single.id, protected.id);
  });

  test('all transport details are inserted and replaced, including false and zero', () async {
    final db = AppDatabase.inMemory(NativeDatabase.memory());
    addTearDown(db.close);
    final source = SubscriptionDataSourceImpl(database: db);
    final sub = await source.addSubscription(
      request: const SubscriptionData(name: 'Test', url: 'https://example.org/api/ct/fictional-token'),
    );
    const incoming = ServerData.empty(
      name: 'Transport',
      h2PaddingFrames: 8,
      h2PaddingFramesMin: 3,
      h2PaddingPerStream: false,
      h2PaddingMinBytes: 0,
      h2PaddingMaxBytes: 256,
      h2PaddingStreamBytes: 8192,
      h2PaddingSessionBytes: 16384,
      keepaliveIntervalSecs: 90,
      keepaliveSignal: 'ping',
      sessionLifetimeSecs: 7200,
      xhttpEnabled: true,
      xhttpPath: '/fictional/',
    );
    await source.syncServersForSubscription(id: sub.id!, servers: [incoming]);
    final serverSource = ServerDataSourceImpl(database: db, deepLinkManager: DeepLinkManagerImpl());
    final first = (await serverSource.getAllServers()).single;
    expect(first.serverData.xhttpEnabled, isTrue);
    expect(first.serverData.xhttpPath, '/fictional/');
    expect(first.serverData.h2PaddingFramesMin, 3);
    expect(first.serverData.h2PaddingPerStream, isFalse);
    expect(first.serverData.h2PaddingMinBytes, 0);
    expect(first.serverData.h2PaddingMaxBytes, 256);
    expect(first.serverData.h2PaddingStreamBytes, 8192);
    expect(first.serverData.h2PaddingSessionBytes, 16384);
    expect(first.serverData.keepaliveIntervalSecs, 90);
    expect(first.serverData.keepaliveSignal, 'ping');
    expect(first.serverData.sessionLifetimeSecs, 7200);
    await source.syncServersForSubscription(
      id: sub.id!,
      servers: [
        incoming.copyWith(
          xhttpEnabled: false,
          xhttpPath: '',
          keepaliveIntervalSecs: 0,
          sessionLifetimeSecs: 0,
          h2PaddingFramesMin: 0,
          h2PaddingSessionBytes: 0,
        ),
      ],
    );
    final updated = (await serverSource.getAllServers()).single.serverData;
    expect(updated.xhttpEnabled, isFalse);
    expect(updated.xhttpPath, '');
    expect(updated.keepaliveIntervalSecs, 0);
    expect(updated.sessionLifetimeSecs, 0);
    expect(updated.h2PaddingFramesMin, 0);
    expect(updated.h2PaddingSessionBytes, 0);
  });
  test('v15 database gains a persistent per-key override defaulting to false', () async {
    final db = AppDatabase.inMemory(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customStatement('ALTER TABLE servers DROP COLUMN subscription_override');
    await db.migration.onUpgrade!(Migrator(db), 15, 16);
    final columns = await db.customSelect('PRAGMA table_info(servers)').get();
    final override = columns.singleWhere((row) => row.read<String>('name') == 'subscription_override');
    expect(override.read<String>('dflt_value').toLowerCase(), 'false');
    expect(override.read<int>('notnull'), 1);
  });

  test('failed restore leaves the override and credentials intact', () async {
    final db = AppDatabase.inMemory(NativeDatabase.memory());
    addTearDown(db.close);
    final source = SubscriptionDataSourceImpl(database: db);
    final sub = await source.addSubscription(
      request: const SubscriptionData(name: 'Legacy', url: 'http://example.org/api/ct/fictional-token'),
    );
    await source.syncServersForSubscription(
      id: sub.id!,
      servers: [const ServerData.empty(name: 'Protected', username: 'manual', password: 'manual-pass')],
    );
    final row = await db.select(db.servers).getSingle();
    await (db.update(
      db.servers,
    )..where((s) => s.id.equals(row.id))).write(const ServersCompanion(subscriptionOverride: Value(true)));
    final serverSource = ServerDataSourceImpl(database: db, deepLinkManager: DeepLinkManagerImpl());
    final original = await serverSource.getServerById(id: row.id.toString());
    final sync = SubscriptionSyncService(subscriptionDataSource: source, serverDataSource: serverSource);
    await expectLater(sync.restoreServer(original), throwsA(isA<SubscriptionFetchException>()));
    final after = await serverSource.getServerById(id: row.id.toString());
    expect(after.serverData, original.serverData);
  });
  test('failed server write rolls back DNS when restoring a key', () async {
    final db = AppDatabase.inMemory(NativeDatabase.memory());
    addTearDown(db.close);
    final source = ServerDataSourceImpl(database: db, deepLinkManager: DeepLinkManagerImpl());
    final original = await source.addNewServer(
      request: const ServerData.empty(name: 'Atomic', routingProfileId: '1', dnsServers: ['192.0.2.53']),
    );
    await db.customStatement(
      "CREATE TRIGGER fail_restore BEFORE UPDATE ON servers "
      "BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END",
    );
    await expectLater(
      source.setNewServer(
        id: original.id,
        request: original.serverData.copyWith(dnsServers: ['192.0.2.54']),
      ),
      throwsA(predicate((error) => error.toString().contains('simulated write failure'))),
    );
    final after = await source.getServerById(id: original.id);
    expect(after.serverData.dnsServers, original.serverData.dnsServers);
  });
  test('restore fetches a real bot-shaped link and clears only the target override', () async {
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoDeviceIdentityPaths();
    addTearDown(() => PathProviderPlatform.instance = previousPaths);
    final db = AppDatabase.inMemory(NativeDatabase.memory());
    addTearDown(db.close);
    final source = SubscriptionDataSourceImpl(database: db);
    final sub = await source.addSubscription(
      request: const SubscriptionData(name: 'Test', url: 'https://example.org/api/ct/fictional-token'),
    );
    await source.syncServersForSubscription(
      id: sub.id!,
      servers: [
        const ServerData.empty(
          name: 'Fictional',
          username: 'manual',
          password: 'manual-pass',
          dnsServers: ['192.0.2.44'],
        ),
      ],
    );
    final row = await db.select(db.servers).getSingle();
    await (db.update(db.servers)..where((s) => s.id.equals(row.id))).write(
      const ServersCompanion(subscriptionOverride: Value(true), selected: Value(true), routingProfileId: Value(1)),
    );
    final serverSource = ServerDataSourceImpl(database: db, deepLinkManager: DeepLinkManagerImpl());
    final original = await serverSource.getServerById(id: row.id.toString());
    final fixture = jsonDecode(File('test/fixtures/bot_subscription_links.json').readAsStringSync()) as Map;
    final sync = SubscriptionSyncService(subscriptionDataSource: source, serverDataSource: serverSource);
    await http.runWithClient(
      () => sync.restoreServer(original),
      () => MockClient((request) async {
        expect(request.url.toString(), 'https://example.org/api/ct/fictional-token');
        return http.Response(fixture['on'] as String, 200);
      }),
    );
    final after = (await serverSource.getServerById(id: row.id.toString())).serverData;
    expect(after.subscriptionOverride, isFalse);
    expect(after.subscriptionId, sub.id);
    expect(after.username, 'fictional-user');
    expect(after.password, 'fictional-password');
    expect(after.dnsServers, ['192.0.2.53']);
    expect(after.xhttpEnabled, isTrue);
    expect(after.keepaliveIntervalSecs, 90);
    expect(after.routingProfileId, '1');
    expect(after.selected, isTrue);
  });
}
