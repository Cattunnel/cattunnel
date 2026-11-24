import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:trusttunnel/data/database/app_database.dart' hide Server;
import 'package:trusttunnel/data/database/migrations/migrations_v19.dart';
import 'package:trusttunnel/data/datasources/local_sources/server_datasource_impl.dart';
import 'package:trusttunnel/data/datasources/local_sources/subscription_datasource_impl.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/server_group_settings.dart';
import 'package:trusttunnel/data/model/server_sort_option.dart';
import 'package:trusttunnel/feature/server/servers/controller/server_latency_controller.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_groups.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_latency_result.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_sorting.dart';
import 'package:vpn_plugin/deep_link_manager.dart';

class _NoLinks implements DeepLinkManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Pings as stored after earlier in-tunnel measurements.
class _Stored implements PingStore {
  final Map<String, ServerLatencyResult> results;
  _Stored(this.results);

  @override
  Map<String, ServerLatencyResult> load() => results;

  @override
  Future<void> save(Map<String, ServerLatencyResult> results) async {}
}

ServerData _entry(String name) => ServerData.empty(
  name: name,
  ipAddress: '192.0.2.${name.codeUnitAt(0)}:443',
  domain: '${name.toLowerCase()}.example.org',
  username: 'bob',
  password: 'pw',
);

void main() {
  late AppDatabase database;
  late SubscriptionDataSourceImpl subscriptions;
  late ServerDataSourceImpl serverSource;
  late int subscriptionId;
  final latency = ServerLatencyController();

  setUpAll(() {
    if (Platform.isLinux && File('/usr/lib/x86_64-linux-gnu/libsqlite3.so.0').existsSync()) {
      open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
    }
  });

  setUp(() async {
    database = AppDatabase.inMemory(NativeDatabase.memory());
    subscriptions = SubscriptionDataSourceImpl(database: database);
    serverSource = ServerDataSourceImpl(database: database, deepLinkManager: _NoLinks());
    subscriptionId = await database
        .into(database.subscriptions)
        .insert(SubscriptionsCompanion.insert(name: 'Family', url: 'https://example.org/sub'));
  });

  tearDown(() => database.close());

  Future<void> refresh(List<String> names) =>
      subscriptions.syncServersForSubscription(id: subscriptionId.toString(), servers: names.map(_entry).toList());

  Future<List<String>> shown(ServerSortOption option, {ServerLatencyController? controller}) async {
    final all = await serverSource.getAllServers();

    return sortServers(all, option, controller ?? latency).map((s) => s.serverData.name).toList();
  }

  Future<Server> byName(String name) async =>
      (await serverSource.getAllServers()).firstWhere((s) => s.serverData.name == name);

  test('a server that left the subscription and came back is shown at its place in the subscription', () async {
    await refresh(['A', 'B', 'C']);
    await refresh(['A', 'C']);
    await refresh(['A', 'B', 'C']);

    expect(await shown(ServerSortOption.origin), ['A', 'B', 'C']);
  });

  test('a favorite stays first and marked after a subscription refresh', () async {
    await refresh(['A', 'B', 'C']);
    await serverSource.setFavorite(serverId: (await byName('B')).id, favorite: true);
    await refresh(['A', 'B', 'C']);

    expect(await shown(ServerSortOption.origin), ['B', 'A', 'C']);
    expect((await byName('B')).favorite, isTrue);
  });

  test('a favorite stays first and marked after leaving the subscription and returning', () async {
    await refresh(['A', 'B', 'C']);
    await serverSource.setFavorite(serverId: (await byName('B')).id, favorite: true);
    await refresh(['A', 'C']);
    expect(await shown(ServerSortOption.origin), ['A', 'C']);
    await refresh(['A', 'B', 'C']);

    expect(await shown(ServerSortOption.origin), ['B', 'A', 'C']);
    expect((await byName('B')).favorite, isTrue);
  });

  test('a favorite survives subscription_override', () async {
    await refresh(['A', 'B', 'C']);
    final b = await byName('B');
    await serverSource.setFavorite(serverId: b.id, favorite: true);
    await (database.update(database.servers)..where((s) => s.id.equals(int.parse(b.id)))).write(
      const ServersCompanion(subscriptionOverride: Value(true)),
    );
    await refresh(['A', 'B', 'C']);

    expect((await byName('B')).favorite, isTrue);
  });

  test('a favorite with no latency measurement is above measured non-favorites', () async {
    await refresh(['A', 'B', 'C']);
    await serverSource.setFavorite(serverId: (await byName('B')).id, favorite: true);

    final controller = ServerLatencyController(
      store: _Stored({
        (await byName('A')).id: ServerLatencyResult(
          latency: const Duration(milliseconds: 30),
          testedAt: DateTime(2026),
        ),
        (await byName('C')).id: ServerLatencyResult(
          latency: const Duration(milliseconds: 10),
          testedAt: DateTime(2026),
        ),
      }),
    );
    addTearDown(controller.dispose);

    expect(await shown(ServerSortOption.latency, controller: controller), ['B', 'C', 'A']);
  });

  test('favorites come first under the name sort too, sorted by name among themselves', () async {
    await refresh(['A', 'B', 'C']);
    await serverSource.setFavorite(serverId: (await byName('C')).id, favorite: true);
    await serverSource.setFavorite(serverId: (await byName('B')).id, favorite: true);

    expect(await shown(ServerSortOption.name), ['B', 'C', 'A']);
  });

  test('a manual server is a favorite by row id and loses the mark when deleted', () async {
    final added = await serverSource.addNewServer(
      request: const ServerData.empty(
        name: 'Own',
        ipAddress: '198.51.100.1:443',
        domain: 'own.example.org',
        username: 'bob',
        password: 'pw',
        routingProfileId: '1',
      ),
    );
    await serverSource.setFavorite(serverId: added.id, favorite: true);
    expect((await byName('Own')).favorite, isTrue);

    await serverSource.removeServer(serverId: added.id);
    expect(await database.select(database.favoriteServers).get(), isEmpty);
  });

  test('deleting a subscription drops its favorites and its group settings', () async {
    await refresh(['A']);
    await serverSource.setFavorite(serverId: (await byName('A')).id, favorite: true);
    await subscriptions.setGroupLabel(key: subscriptionGroupKey('$subscriptionId'), label: 'Дом');
    await subscriptions.removeSubscription(id: subscriptionId.toString());

    expect(await database.select(database.favoriteServers).get(), isEmpty);
    expect(await subscriptions.getGroupSettings(), isEmpty);
  });

  test('the order of groups persists across a subscription refresh', () async {
    await refresh(['A']);
    final subscriptionKey = subscriptionGroupKey('$subscriptionId');
    final defaults = [manualGroupKey, subscriptionKey];
    // Owner 20.11: «подписка 1, подписка 2, Свои ключи», the manual group goes last by default.
    expect(orderGroupKeys(defaults, await subscriptions.getGroupSettings()), [subscriptionKey, manualGroupKey]);

    await subscriptions.setGroupOrder(keys: [manualGroupKey, subscriptionKey]);
    await refresh(['A', 'B']);

    expect(orderGroupKeys(defaults, await subscriptions.getGroupSettings()), [manualGroupKey, subscriptionKey]);
  });

  test('a group label survives a refresh and does not detach servers from their subscription', () async {
    await refresh(['A', 'B']);
    final key = subscriptionGroupKey('$subscriptionId');
    await subscriptions.setGroupLabel(key: key, label: '  Дом  ');
    await refresh(['A', 'B', 'C']);

    final settings = await subscriptions.getGroupSettings();
    expect(groupDisplayName('Family', settings[key]), 'Дом');
    final all = await serverSource.getAllServers();
    expect(all.map((s) => s.serverData.subscriptionName).toSet(), {'Family'});
    expect(all.map((s) => s.serverData.subscriptionId).toSet(), {'$subscriptionId'});
    expect((await subscriptions.getAllSubscriptions()).single.name, 'Family');

    await subscriptions.setGroupLabel(key: key, label: '');
    expect(groupDisplayName('Family', (await subscriptions.getGroupSettings())[key]), 'Family');
  });

  test('the manual group is last by default; a new subscription goes after ordered groups', () {
    const settings = {'s:1': ServerGroupSettings(position: 0)};
    expect(orderGroupKeys(['m', 's:1', 's:2'], const {}), ['s:1', 's:2', 'm']);
    expect(orderGroupKeys(['m', 's:1', 's:2'], settings), ['s:1', 's:2', 'm']);
    expect(orderGroupKeys(['m', 's:1', 's:2'], {'s:2': const ServerGroupSettings(position: 0)}), ['s:2', 's:1', 'm']);
    expect(
      orderGroupKeys(
        ['m', 's:1', 's:2'],
        {'m': const ServerGroupSettings(position: 0), 's:1': const ServerGroupSettings(position: 1)},
      ),
      ['m', 's:1', 's:2'],
    );
    expect(moveGroupKey(['m', 's:1', 's:2'], 's:2', -1), ['m', 's:2', 's:1']);
    expect(moveGroupKey(['m', 's:1'], 'm', -1), ['m', 's:1']);
  });

  test('migration to v19 numbers existing subscription rows by id and creates the new tables', () async {
    await refresh(['A', 'B', 'C']);
    // The shape of a v18 database: no position column, no new tables.
    await database.customStatement('UPDATE servers SET subscription_position = NULL');
    await database.customStatement('DROP TABLE favorite_servers');
    await database.customStatement('DROP TABLE server_groups');

    await const MigrationsV19().migrate(database, database.createMigrator());

    final rows = await (database.select(database.servers)..orderBy([(s) => OrderingTerm.asc(s.id)])).get();
    expect(rows.map((r) => r.subscriptionPosition), [0, 1, 2]);
    expect(await database.select(database.favoriteServers).get(), isEmpty);
    expect(await database.select(database.serverGroups).get(), isEmpty);
  });
}
