import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:trusttunnel/data/database/app_database.dart';

/// What v19 (server order, favorites, groups; item 12) and v20 (rotation 9a,
/// CatTail; 1.5.9.5) added. Dropping them gives the table a v18 build wrote.
const _v19Columns = ['subscription_position'];
const _v20Columns = [
  'rotation_addresses',
  'rotation_enabled',
  'rotation_min_secs',
  'rotation_max_secs',
  'cattail_enabled',
  'cattail_ports',
  'cattail_key',
  'cattail_pattern',
];

void main() {
  setUpAll(() {
    if (Platform.isLinux && File('/usr/lib/x86_64-linux-gnu/libsqlite3.so.0').existsSync()) {
      open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
    }
  });

  late Directory dir;
  late File path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cattunnel_v20_');
    path = File('${dir.path}/app.db');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<Set<String>> columnsOf(AppDatabase db) async =>
      (await db.customSelect('PRAGMA table_info(servers)').get()).map((row) => row.read<String>('name')).toSet();

  /// A file database in the shape of v18 with two servers, one from a subscription.
  Future<void> writeV18() async {
    final db = AppDatabase.inMemory(NativeDatabase(path));
    final subscription = await db
        .into(db.subscriptions)
        .insert(
          SubscriptionsCompanion.insert(name: 'Family', url: 'https://example.org/sub'),
        );
    for (final column in [..._v19Columns, ..._v20Columns]) {
      await db.customStatement('ALTER TABLE servers DROP COLUMN $column');
    }
    await db.customStatement('DROP TABLE favorite_servers');
    await db.customStatement('DROP TABLE server_groups');
    await db.customStatement(
      'INSERT INTO servers (ip_address, name, domain, login, password, vpn_protocol_id, routing_profile_id) '
      "VALUES ('1.2.3.4:443', 'Own', 'own.example.org', 'bob', 'pw', 1, 1)",
    );
    await db.customStatement(
      'INSERT INTO servers (ip_address, name, domain, login, password, vpn_protocol_id, routing_profile_id, subscription_id) '
      "VALUES ('5.6.7.8:443', 'Sub', 'sub.example.org', 'ann', 'pw2', 1, 1, $subscription)",
    );
    await db.customStatement("UPDATE servers SET tls_profile = 'safari' WHERE name = 'Own'");
    await db.customStatement('PRAGMA user_version = 18');
    expect((await columnsOf(db)).intersection({..._v19Columns, ..._v20Columns}), isEmpty);
    await db.close();
  }

  test('opening a v18 database runs v19 and v20 through the app migration and keeps the rows', () async {
    await writeV18();

    final db = AppDatabase.inMemory(NativeDatabase(path));
    addTearDown(db.close);

    expect(await columnsOf(db), containsAll([..._v19Columns, ..._v20Columns]));
    expect((await db.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version'), 20);

    final rows = await (db.select(db.servers)..orderBy([(s) => OrderingTerm.asc(s.id)])).get();
    expect(rows.map((r) => [r.name, r.login, r.password]), [
      ['Own', 'bob', 'pw'],
      ['Sub', 'ann', 'pw2'],
    ]);
    // v19: the subscription row got its position, the manual one none.
    expect(rows.map((r) => r.subscriptionPosition), [null, 0]);
    expect(rows.map((r) => r.tlsProfile), ['', '']);
    // v20: no rotation and no CatTail on old rows.
    for (final row in rows) {
      expect(row.rotationAddresses, isEmpty);
      expect(row.rotationEnabled, isFalse);
      expect([row.rotationMinSecs, row.rotationMaxSecs], [0, 0]);
      expect(row.cattailEnabled, isFalse);
      expect([row.cattailPorts, row.cattailKey, row.cattailPattern], ['', '', '']);
    }
  });

  test('after the migration the new fields are written and read back', () async {
    await writeV18();
    final db = AppDatabase.inMemory(NativeDatabase(path));
    addTearDown(db.close);

    await (db.update(db.servers)..where((s) => s.name.equals('Sub'))).write(
      const ServersCompanion(
        rotationAddresses: Value(['www.example.org:443 www.example.org de.example.org', '5.6.7.9:443']),
        rotationEnabled: Value(true),
        rotationMinSecs: Value(600),
        rotationMaxSecs: Value(900),
        cattailEnabled: Value(true),
        cattailPorts: Value('20000-40000'),
        cattailKey: Value('AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8='),
        cattailPattern: Value('stop=1\n0=400-1400'),
      ),
    );

    final row = await (db.select(db.servers)..where((s) => s.name.equals('Sub'))).getSingle();
    expect(row.rotationAddresses, ['www.example.org:443 www.example.org de.example.org', '5.6.7.9:443']);
    expect([row.rotationEnabled, row.rotationMinSecs, row.rotationMaxSecs], [true, 600, 900]);
    expect(
      [row.cattailEnabled, row.cattailPorts, row.cattailKey, row.cattailPattern],
      [
        true,
        '20000-40000',
        'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=',
        'stop=1\n0=400-1400',
      ],
    );
  });

  test('running v20 twice on a migrated database is harmless', () async {
    await writeV18();
    var db = AppDatabase.inMemory(NativeDatabase(path));
    await db.customStatement('PRAGMA user_version = 19');
    await db.close();

    db = AppDatabase.inMemory(NativeDatabase(path));
    addTearDown(db.close);
    expect(await columnsOf(db), containsAll(_v20Columns));
    expect(await db.select(db.servers).get(), hasLength(2));
  });
}
