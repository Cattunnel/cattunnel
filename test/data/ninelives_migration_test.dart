import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:trusttunnel/data/database/app_database.dart';
import 'package:trusttunnel/data/database/migrations/migrations_v17.dart';

/// The columns version 17 added: the NineLives key and the local switch.
const _newColumns = ['xhttp_server_key', 'xhttp_encryption_enabled'];

void main() {
  setUpAll(() {
    // A desktop Linux has the runtime library only (no -dev symlink).
    if (Platform.isLinux && File('/usr/lib/x86_64-linux-gnu/libsqlite3.so.0').existsSync()) {
      open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
    }
  });

  Future<AppDatabase> olderDatabase() async {
    final db = AppDatabase.inMemory(NativeDatabase.memory());
    addTearDown(db.close);

    // Make the table look like version 16 wrote it.
    for (final column in _newColumns) {
      await db.customStatement('ALTER TABLE servers DROP COLUMN $column');
    }
    await db.customStatement(
      'INSERT INTO servers (ip_address, name, domain, login, password, vpn_protocol_id, routing_profile_id) '
      "VALUES ('1.2.3.4:443', 'Old', 'old.example.org', 'bob', 'pw', 1, 1)",
    );

    return db;
  }

  test('migration v17 adds the NineLives fields to an older database', () async {
    final db = await olderDatabase();

    await const MigrationsV17().migrate(db, Migrator(db));

    final server = await db.select(db.servers).getSingle();
    expect(server.name, 'Old');
    expect(server.xhttpServerKey, '');
    // The switch is on by default; without a key the UI keeps it off.
    expect(server.xhttpEncryptionEnabled, true);
  });

  test('migration v17 keeps the values a user has already set and runs twice safely', () async {
    final db = await olderDatabase();

    await const MigrationsV17().migrate(db, Migrator(db));
    await const MigrationsV17().migrate(db, Migrator(db));

    await (db.update(db.servers)..where((s) => s.name.equals('Old'))).write(
      const ServersCompanion(
        xhttpServerKey: Value('public-key'),
        xhttpEncryptionEnabled: Value(false),
      ),
    );

    final server = await db.select(db.servers).getSingle();
    expect(server.xhttpServerKey, 'public-key');
    expect(server.xhttpEncryptionEnabled, false);
  });
}
