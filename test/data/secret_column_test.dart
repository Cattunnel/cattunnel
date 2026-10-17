import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:trusttunnel/data/database/app_database.dart';
import 'package:trusttunnel/data/database/migrations/migrations_v14.dart';
import 'package:trusttunnel/data/database/secret_column.dart';

void main() {
  setUpAll(() {
    // A desktop Linux has the runtime library only (no -dev symlink).
    if (Platform.isLinux && File('/usr/lib/x86_64-linux-gnu/libsqlite3.so.0').existsSync()) {
      open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
    }
    SecretColumn.useKey(Uint8List.fromList(List<int>.generate(32, (i) => i)));
  });

  test('secret columns are sealed in the file and read back in clear', () async {
    final db = AppDatabase.inMemory(NativeDatabase.memory());
    addTearDown(db.close);

    final subId = await db
        .into(db.subscriptions)
        .insert(
          SubscriptionsCompanion.insert(
            name: 'Sub',
            url: 'https://example.org/api/ct/TOKEN',
            agePrivateKey: const Value('AGE-SECRET-KEY-1X'),
          ),
        );
    final serverId = await db
        .into(db.servers)
        .insert(
          ServersCompanion.insert(
            ipAddress: '203.0.113.5:443',
            name: 'S',
            domain: 'vpn.example.org',
            login: 'alice',
            password: 's3cr3t',
            vpnProtocolId: 1,
            routingProfileId: 1,
            clientRandomAuthKey: const Value('00112233445566778899aabbccddeeff'),
            subscriptionId: Value(subId),
          ),
        );

    final raw = await db
        .customSelect(
          'SELECT login, password, client_random_auth_key FROM servers WHERE id = ?',
          variables: [Variable(serverId)],
        )
        .getSingle();
    for (final column in ['login', 'password', 'client_random_auth_key']) {
      expect(raw.read<String>(column), startsWith('enc1:'), reason: column);
    }
    final rawSub = await db.customSelect('SELECT url, age_private_key FROM subscriptions').getSingle();
    expect(rawSub.read<String>('url'), startsWith('enc1:'));
    expect(rawSub.read<String>('age_private_key'), startsWith('enc1:'));
    expect(rawSub.read<String>('url'), isNot(contains('TOKEN')));

    final server = await (db.select(db.servers)..where((s) => s.id.equals(serverId))).getSingle();
    expect(server.login, 'alice');
    expect(server.password, 's3cr3t');
    expect(server.clientRandomAuthKey, '00112233445566778899aabbccddeeff');
    final sub = await db.select(db.subscriptions).getSingle();
    expect(sub.url, 'https://example.org/api/ct/TOKEN');
    expect(sub.agePrivateKey, 'AGE-SECRET-KEY-1X');
  });

  test('migration v14 seals plain values left by an older version, sealed ones stay', () async {
    final db = AppDatabase.inMemory(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customStatement(
      "INSERT INTO subscriptions (name, url, age_private_key) VALUES ('Old', 'https://example.org/old', NULL)",
    );
    await db.customStatement(
      'INSERT INTO servers (ip_address, name, domain, login, password, vpn_protocol_id, routing_profile_id) '
      "VALUES ('1.2.3.4:443', 'Old', 'old.example.org', 'bob', 'pw', 1, 1)",
    );
    final sealedBefore = SecretColumn.seal('kept');
    await db.customStatement('UPDATE servers SET client_random_auth_key = ?', [sealedBefore]);

    await const MigrationsV14().migrate(db, Migrator(db));

    final raw = await db.customSelect('SELECT login, password, client_random_auth_key FROM servers').getSingle();
    expect(raw.read<String>('login'), startsWith('enc1:'));
    expect(raw.read<String>('password'), startsWith('enc1:'));
    expect(raw.read<String>('client_random_auth_key'), sealedBefore);
    final server = await db.select(db.servers).getSingle();
    expect([server.login, server.password, server.clientRandomAuthKey], ['bob', 'pw', 'kept']);
    final sub = await db.select(db.subscriptions).getSingle();
    expect(sub.url, 'https://example.org/old');
    expect(sub.agePrivateKey, isNull);
  });

  test('a value sealed with another key reads empty instead of crashing', () {
    final sealed = SecretColumn.seal('x');
    SecretColumn.useKey(Uint8List(32));
    expect(SecretColumn.open(sealed), '');
    SecretColumn.useKey(Uint8List.fromList(List<int>.generate(32, (i) => i)));
    expect(SecretColumn.open(sealed), 'x');
  });
}
