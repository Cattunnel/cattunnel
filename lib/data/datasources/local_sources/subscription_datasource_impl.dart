import 'package:drift/drift.dart';
import 'package:trusttunnel/common/utils/certificate_encoders.dart';
import 'package:trusttunnel/common/utils/routing_profile_utils.dart';
import 'package:trusttunnel/data/database/app_database.dart' as db;
import 'package:trusttunnel/data/datasources/local_sources/favorite_key.dart';
import 'package:trusttunnel/data/datasources/subscription_datasource.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/server_group_settings.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';

class SubscriptionDataSourceImpl implements SubscriptionDataSource {
  final db.AppDatabase database;

  SubscriptionDataSourceImpl({
    required this.database,
  });

  @override
  Future<List<SubscriptionData>> getAllSubscriptions() async {
    final rows = await database.select(database.subscriptions).get();

    return rows.map(_toDomain).toList();
  }

  @override
  Future<SubscriptionData> addSubscription({required SubscriptionData request}) async {
    final id = await database.subscriptions.insertOnConflictUpdate(
      db.SubscriptionsCompanion.insert(
        name: request.name,
        url: request.url,
        skipVerification: Value(request.skipVerification),
        autoRefreshEnabled: Value(request.autoRefreshEnabled),
        agePrivateKey: Value(request.agePrivateKey),
      ),
    );

    return request._withId(id.toString());
  }

  @override
  Future<void> updateSubscription({required String id, required SubscriptionData request}) async {
    final parsedId = int.parse(id);

    await (database.subscriptions.update()..where((s) => s.id.equals(parsedId))).write(
      db.SubscriptionsCompanion(
        name: Value(request.name),
        url: Value(request.url),
        skipVerification: Value(request.skipVerification),
        autoRefreshEnabled: Value(request.autoRefreshEnabled),
        agePrivateKey: Value(request.agePrivateKey),
      ),
    );
  }

  @override
  Future<void> removeSubscription({required String id}) async {
    final parsedId = int.parse(id);

    await database.transaction(() async {
      final owned = await (database.select(
        database.servers,
      )..where((s) => s.subscriptionId.equals(parsedId))).get();

      for (final server in owned) {
        await _deleteServerRow(server.id);
      }

      await database.favoriteServers.deleteWhere((f) => f.favKey.like(favoriteKeyPrefixOf(parsedId)));
      await database.serverGroups.deleteWhere((g) => g.groupKey.equals(subscriptionGroupKey(id)));
      await database.subscriptions.deleteWhere((s) => s.id.equals(parsedId));
    });
  }

  @override
  Future<Map<String, ServerGroupSettings>> getGroupSettings() async {
    final rows = await database.select(database.serverGroups).get();

    return {for (final row in rows) row.groupKey: ServerGroupSettings(label: row.label, position: row.position)};
  }

  @override
  Future<void> setGroupLabel({required String key, required String label}) async {
    final trimmed = label.trim();
    final updated = await (database.update(
      database.serverGroups,
    )..where((g) => g.groupKey.equals(key))).write(db.ServerGroupsCompanion(label: Value(trimmed)));
    if (updated == 0) {
      await database.serverGroups.insertOne(db.ServerGroupsCompanion.insert(groupKey: key, label: Value(trimmed)));
    }
  }

  @override
  Future<void> setGroupOrder({required List<String> keys}) => database.transaction(() async {
    for (final (index, key) in keys.indexed) {
      final updated = await (database.update(
        database.serverGroups,
      )..where((g) => g.groupKey.equals(key))).write(db.ServerGroupsCompanion(position: Value(index)));
      if (updated == 0) {
        await database.serverGroups.insertOne(db.ServerGroupsCompanion.insert(groupKey: key, position: Value(index)));
      }
    }
  });

  @override
  Future<void> markRefreshed({required String id, required DateTime at}) async {
    final parsedId = int.parse(id);

    await (database.subscriptions.update()..where((s) => s.id.equals(parsedId))).write(
      db.SubscriptionsCompanion(
        lastUpdatedAt: Value(at.toIso8601String()),
      ),
    );
  }

  @override
  Future<void> syncServersForSubscription({
    required String id,
    required List<ServerData> servers,
  }) async {
    final subscriptionId = int.parse(id);

    await database.transaction(() async {
      final existingRows = await (database.select(
        database.servers,
      )..where((s) => s.subscriptionId.equals(subscriptionId))).get();

      final existingByName = {for (final row in existingRows) row.name: row};
      final incomingNames = servers.map((s) => s.name).toSet();

      for (final row in existingRows) {
        if (!incomingNames.contains(row.name) && !row.selected && !row.subscriptionOverride) {
          await _deleteServerRow(row.id);
        }
      }

      // Servers are matched by name, so a duplicate name in one response
      // would overwrite the first entry - keep the first, skip the rest.
      // The position is the index among the servers actually taken, so it is
      // the order of the response. Favorites are keyed by name and are not
      // touched here: they outlive a deleted row.
      final seenNames = <String>{};
      var position = 0;
      for (final server in servers) {
        if (!seenNames.add(server.name)) {
          continue;
        }

        final existing = existingByName[server.name];

        if (existing != null) {
          if (existing.subscriptionOverride) {
            await _writePosition(existing.id, position);
          } else {
            await _updateServerRow(existing.id, server, position);
          }
        } else {
          await _insertServerRow(subscriptionId, server, position);
        }
        position++;
      }
    });
  }

  Future<void> _insertServerRow(int subscriptionId, ServerData server, int position) async {
    final id = await database.servers.insertOnConflictUpdate(
      db.ServersCompanion.insert(
        ipAddress: server.ipAddress,
        name: server.name,
        domain: server.domain,
        login: server.username,
        password: server.password,
        vpnProtocolId: server.vpnProtocol.value,
        ipv6Enabled: Value(server.ipv6),
        antiDpi: Value(server.antiDpi),
        antiDpiMode: Value(server.antiDpiMode),
        tlsProfile: Value(server.tlsProfile),
        clientRandomAuthKey: Value(server.tlsAuthKey),
        antiDpiDesync: Value(server.antiDpiDesync),
        h2PaddingFrames: Value(server.h2PaddingFrames),
        h2PaddingFramesMin: Value(server.h2PaddingFramesMin),
        h2PaddingPerStream: Value(server.h2PaddingPerStream),
        h2PaddingMinBytes: Value(server.h2PaddingMinBytes),
        h2PaddingMaxBytes: Value(server.h2PaddingMaxBytes),
        h2PaddingStreamBytes: Value(server.h2PaddingStreamBytes),
        h2PaddingSessionBytes: Value(server.h2PaddingSessionBytes),
        keepaliveIntervalSecs: Value(server.keepaliveIntervalSecs),
        keepaliveSignal: Value(server.keepaliveSignal),
        sessionLifetimeSecs: Value(server.sessionLifetimeSecs),
        xhttpEnabled: Value(server.xhttpEnabled),
        xhttpPath: Value(server.xhttpPath),
        xhttpServerKey: Value(server.xhttpServerKey),
        sniPool: Value(server.sniPool),
        rotationAddresses: Value(server.rotationAddresses),
        rotationEnabled: Value(server.rotationEnabled),
        rotationMinSecs: Value(server.rotationMinSecs),
        rotationMaxSecs: Value(server.rotationMaxSecs),
        cattailEnabled: Value(server.cattailEnabled),
        cattailPorts: Value(server.cattailPorts),
        cattailKey: Value(server.cattailKey),
        cattailPattern: Value(server.cattailPattern),
        xhttpEncryptionEnabled: Value(server.xhttpEncryptionEnabled),
        blockQuic: Value(server.blockQuic),
        ruExit: Value(server.ruExit),
        tlsPrefix: const Value(null),
        routingProfileId: int.parse(RoutingProfileUtils.defaultRoutingProfileId),
        customSni: Value(server.customSni),
        subscriptionId: Value(subscriptionId),
        subscriptionPosition: Value(position),
      ),
    );

    await database.dnsServers.insertAll(
      server.dnsServers.map(
        (s) => db.DnsServersCompanion.insert(
          serverId: id,
          data: s,
        ),
      ),
    );

    if (server.certificate != null) {
      await database.certificateTable.insertOnConflictUpdate(
        CertificateEncoder(serverId: id).convert(server.certificate!),
      );
    }
  }

  Future<void> _writePosition(int rowId, int position) => (database.servers.update()..where((s) => s.id.equals(rowId)))
      .write(db.ServersCompanion(subscriptionPosition: Value(position)));

  Future<void> _updateServerRow(int rowId, ServerData server, int position) async {
    await (database.servers.update()..where((s) => s.id.equals(rowId))).write(
      db.ServersCompanion(
        subscriptionPosition: Value(position),
        ipAddress: Value(server.ipAddress),
        domain: Value(server.domain),
        login: Value(server.username),
        password: Value(server.password),
        vpnProtocolId: Value(server.vpnProtocol.value),
        ipv6Enabled: Value(server.ipv6),
        antiDpi: Value(server.antiDpi),
        antiDpiMode: Value(server.antiDpiMode),
        tlsProfile: Value(server.tlsProfile),
        antiDpiDesync: Value(server.antiDpiDesync),
        h2PaddingFrames: Value(server.h2PaddingFrames),
        h2PaddingFramesMin: Value(server.h2PaddingFramesMin),
        h2PaddingPerStream: Value(server.h2PaddingPerStream),
        h2PaddingMinBytes: Value(server.h2PaddingMinBytes),
        h2PaddingMaxBytes: Value(server.h2PaddingMaxBytes),
        h2PaddingStreamBytes: Value(server.h2PaddingStreamBytes),
        h2PaddingSessionBytes: Value(server.h2PaddingSessionBytes),
        keepaliveIntervalSecs: Value(server.keepaliveIntervalSecs),
        keepaliveSignal: Value(server.keepaliveSignal),
        sessionLifetimeSecs: Value(server.sessionLifetimeSecs),
        xhttpEnabled: Value(server.xhttpEnabled),
        xhttpPath: Value(server.xhttpPath),
        // The key comes from the subscription; the encryption switch is local.
        xhttpServerKey: Value(server.xhttpServerKey),
        sniPool: Value(server.sniPool),
        rotationAddresses: Value(server.rotationAddresses),
        rotationEnabled: Value(server.rotationEnabled),
        rotationMinSecs: Value(server.rotationMinSecs),
        rotationMaxSecs: Value(server.rotationMaxSecs),
        cattailEnabled: Value(server.cattailEnabled),
        cattailPorts: Value(server.cattailPorts),
        cattailKey: Value(server.cattailKey),
        cattailPattern: Value(server.cattailPattern),
        blockQuic: Value(server.blockQuic),
        // The subscription decides which key has a Russian exit.
        ruExit: Value(server.ruExit),
        tlsPrefix: const Value(null),
        // The key is a credential like the password: the subscription owns it.
        clientRandomAuthKey: Value(server.tlsAuthKey),
        customSni: Value(server.customSni),
      ),
    );

    await database.dnsServers.deleteWhere((d) => d.serverId.equals(rowId));
    await database.dnsServers.insertAll(
      server.dnsServers.map(
        (s) => db.DnsServersCompanion.insert(
          serverId: rowId,
          data: s,
        ),
      ),
    );

    if (server.certificate != null) {
      await database.certificateTable.insertOnConflictUpdate(
        CertificateEncoder(serverId: rowId).convert(server.certificate!),
      );
    } else {
      await database.certificateTable.deleteWhere((c) => c.serverId.equals(rowId));
    }
  }

  Future<void> _deleteServerRow(int rowId) async {
    await database.dnsServers.deleteWhere((d) => d.serverId.equals(rowId));
    await database.certificateTable.deleteWhere((c) => c.serverId.equals(rowId));
    await database.servers.deleteWhere((s) => s.id.equals(rowId));
  }

  SubscriptionData _toDomain(db.Subscription row) => SubscriptionData(
    id: row.id.toString(),
    name: row.name,
    url: row.url,
    skipVerification: row.skipVerification,
    autoRefreshEnabled: row.autoRefreshEnabled,
    lastUpdatedAt: row.lastUpdatedAt == null ? null : DateTime.tryParse(row.lastUpdatedAt!),
    agePrivateKey: row.agePrivateKey,
  );
}

extension on SubscriptionData {
  SubscriptionData _withId(String id) => SubscriptionData(
    id: id,
    name: name,
    url: url,
    skipVerification: skipVerification,
    lastUpdatedAt: lastUpdatedAt,
    autoRefreshEnabled: autoRefreshEnabled,
    agePrivateKey: agePrivateKey,
  );
}
