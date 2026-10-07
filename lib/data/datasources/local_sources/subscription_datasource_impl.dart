import 'package:drift/drift.dart';
import 'package:trusttunnel/common/utils/certificate_encoders.dart';
import 'package:trusttunnel/common/utils/routing_profile_utils.dart';
import 'package:trusttunnel/data/database/app_database.dart' as db;
import 'package:trusttunnel/data/datasources/subscription_datasource.dart';
import 'package:trusttunnel/data/model/server_data.dart';
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

      await database.subscriptions.deleteWhere((s) => s.id.equals(parsedId));
    });
  }

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
        if (!incomingNames.contains(row.name) && !row.selected) {
          await _deleteServerRow(row.id);
        }
      }

      // Servers are matched by name, so a duplicate name in one response
      // would overwrite the first entry - keep the first, skip the rest.
      final seenNames = <String>{};
      for (final server in servers) {
        if (!seenNames.add(server.name)) {
          continue;
        }

        final existing = existingByName[server.name];

        if (existing != null) {
          await _updateServerRow(existing.id, server);
        } else {
          await _insertServerRow(subscriptionId, server);
        }
      }
    });
  }

  Future<void> _insertServerRow(int subscriptionId, ServerData server) async {
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
        antiDpiDesync: Value(server.antiDpiDesync),
        h2PaddingFrames: Value(server.h2PaddingFrames),
        blockQuic: Value(server.blockQuic),
        ruExit: Value(server.ruExit),
        tlsPrefix: Value(server.tlsPrefix),
        routingProfileId: int.parse(RoutingProfileUtils.defaultRoutingProfileId),
        customSni: Value(server.customSni),
        subscriptionId: Value(subscriptionId),
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

  Future<void> _updateServerRow(int rowId, ServerData server) async {
    await (database.servers.update()..where((s) => s.id.equals(rowId))).write(
      db.ServersCompanion(
        ipAddress: Value(server.ipAddress),
        domain: Value(server.domain),
        login: Value(server.username),
        password: Value(server.password),
        vpnProtocolId: Value(server.vpnProtocol.value),
        ipv6Enabled: Value(server.ipv6),
        // A link can turn anti-DPI on; it never turns off the user's own pick.
        antiDpi: server.antiDpi ? const Value(true) : const Value.absent(),
        // The same for the technique: set only when the link names one.
        antiDpiMode: server.antiDpi && server.antiDpiMode != 0 ? Value(server.antiDpiMode) : const Value.absent(),
        // Likewise the fingerprint: only when the link names one.
        tlsProfile: server.tlsProfile.isNotEmpty ? Value(server.tlsProfile) : const Value.absent(),
        // And the custom split (it comes with mode 5, set just above).
        antiDpiDesync: server.antiDpiDesync.isNotEmpty ? Value(server.antiDpiDesync) : const Value.absent(),
        // Padding and QUIC off too: only when the link turns them on.
        h2PaddingFrames: server.h2PaddingFrames > 0 ? Value(server.h2PaddingFrames) : const Value.absent(),
        blockQuic: server.blockQuic ? const Value(true) : const Value.absent(),
        // The subscription decides which key has a Russian exit.
        ruExit: Value(server.ruExit),
        tlsPrefix: Value(server.tlsPrefix),
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
