import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:trusttunnel/data/database/app_database.dart';
import 'package:trusttunnel/data/database/migrations/migrations_v15.dart';

/// The columns version 15 added: the numbers of the traffic shaper, the
/// keepalive and the XHTTP transport.
const _newColumns = [
  'h2_padding_frames_min',
  'h2_padding_per_stream',
  'h2_padding_min_bytes',
  'h2_padding_max_bytes',
  'h2_padding_stream_bytes',
  'h2_padding_session_bytes',
  'keepalive_interval_secs',
  'keepalive_signal',
  'session_lifetime_secs',
  'xhttp_enabled',
  'xhttp_path',
];

void main() {
  setUpAll(() {
    // A desktop Linux has the runtime library only (no -dev symlink).
    if (Platform.isLinux && File('/usr/lib/x86_64-linux-gnu/libsqlite3.so.0').existsSync()) {
      open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
    }
  });

  test('migration v15 adds the expert settings to an older database', () async {
    final db = AppDatabase.inMemory(NativeDatabase.memory());
    addTearDown(db.close);

    // Make the table look like version 14 wrote it.
    for (final column in _newColumns) {
      await db.customStatement('ALTER TABLE servers DROP COLUMN $column');
    }
    await db.customStatement(
      'INSERT INTO servers (ip_address, name, domain, login, password, vpn_protocol_id, routing_profile_id) '
      "VALUES ('1.2.3.4:443', 'Old', 'old.example.org', 'bob', 'pw', 1, 1)",
    );

    await const MigrationsV15().migrate(db, Migrator(db));

    final server = await db.select(db.servers).getSingle();
    expect(server.name, 'Old');
    // The engine's own defaults, so a server that never used them behaves
    // exactly as before.
    expect(server.h2PaddingFramesMin, 2);
    expect(server.h2PaddingPerStream, true);
    expect(server.h2PaddingMinBytes, 1);
    expect(server.h2PaddingMaxBytes, 64);
    expect(server.h2PaddingStreamBytes, 2048);
    expect(server.h2PaddingSessionBytes, 4096);
    expect(server.keepaliveIntervalSecs, 0);
    expect(server.keepaliveSignal, '');
    expect(server.sessionLifetimeSecs, 0);
    expect(server.xhttpEnabled, false);
    expect(server.xhttpPath, '');
  });

  test('migration v15 keeps the values a user has already set', () async {
    final db = AppDatabase.inMemory(NativeDatabase.memory());
    addTearDown(db.close);

    for (final column in _newColumns) {
      await db.customStatement('ALTER TABLE servers DROP COLUMN $column');
    }
    await db.customStatement(
      'INSERT INTO servers (ip_address, name, domain, login, password, vpn_protocol_id, routing_profile_id) '
      "VALUES ('1.2.3.4:443', 'Old', 'old.example.org', 'bob', 'pw', 1, 1)",
    );

    await const MigrationsV15().migrate(db, Migrator(db));
    // The migration is safe to run twice: a column that is already there is
    // left alone.
    await const MigrationsV15().migrate(db, Migrator(db));

    await (db.update(db.servers)..where((s) => s.name.equals('Old'))).write(
      ServersCompanion(
        h2PaddingFramesMin: const Value(3),
        keepaliveIntervalSecs: const Value(60),
        keepaliveSignal: const Value('ping'),
        xhttpEnabled: const Value(true),
        xhttpPath: const Value('/api/v2/'),
      ),
    );

    final server = await db.select(db.servers).getSingle();
    expect(server.h2PaddingFramesMin, 3);
    expect(server.keepaliveIntervalSecs, 60);
    expect(server.keepaliveSignal, 'ping');
    expect(server.xhttpEnabled, true);
    expect(server.xhttpPath, '/api/v2/');
  });
}
