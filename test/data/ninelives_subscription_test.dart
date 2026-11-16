import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:trusttunnel/data/database/app_database.dart';
import 'package:trusttunnel/data/datasources/local_sources/subscription_datasource_impl.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/vpn_protocol.dart';

void main() {
  setUpAll(() {
    if (Platform.isLinux && File('/usr/lib/x86_64-linux-gnu/libsqlite3.so.0').existsSync()) {
      open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
    }
  });

  test('a subscription refresh replaces the key and keeps the local NineLives switch', () async {
    final database = AppDatabase.inMemory(NativeDatabase.memory());
    addTearDown(database.close);

    final subscriptionId = await database.into(database.subscriptions).insert(
      SubscriptionsCompanion.insert(name: 'Family', url: 'https://example.org/sub'),
    );
    await database.into(database.servers).insert(
      ServersCompanion.insert(
        ipAddress: '1.2.3.4:443',
        name: 'S',
        domain: 's.example.org',
        login: 'bob',
        password: 'pw',
        vpnProtocolId: VpnProtocol.http2.value,
        routingProfileId: 1,
        xhttpEnabled: const Value(true),
        xhttpServerKey: const Value('old-key'),
        xhttpEncryptionEnabled: const Value(false),
        subscriptionId: Value(subscriptionId),
      ),
    );

    final datasource = SubscriptionDataSourceImpl(database: database);
    await datasource.syncServersForSubscription(
      id: subscriptionId.toString(),
      servers: const [
        ServerData.empty(
          name: 'S',
          ipAddress: '1.2.3.4:443',
          domain: 's.example.org',
          username: 'bob',
          password: 'pw',
          xhttpEnabled: true,
          xhttpServerKey: 'new-key',
        ),
      ],
    );

    final row = await database.select(database.servers).getSingle();
    expect(row.xhttpServerKey, 'new-key');
    expect(row.xhttpEncryptionEnabled, false);
  });
}
