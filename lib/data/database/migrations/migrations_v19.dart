import 'package:drift/drift.dart';
import 'package:trusttunnel/data/database/app_database.dart' as db;
import 'package:trusttunnel/data/database/migrations/migrations.dart';

/// Server order as in the subscription (servers.subscription_position), the
/// favorite_servers table and the server_groups table (group labels, order). Existing subscription rows get their order by
/// row id, the best the old data can tell.
class MigrationsV19 implements Migrations {
  const MigrationsV19();

  @override
  Future<void> migrate(GeneratedDatabase database, Migrator m) async {
    final appDatabase = database as db.AppDatabase;

    final columns = await appDatabase.customSelect('PRAGMA table_info(servers)').get();
    final names = columns.map((row) => row.read<String>('name')).toSet();

    if (!names.contains('subscription_position')) {
      await m.addColumn(
        appDatabase.servers,
        appDatabase.servers.subscriptionPosition,
      );
    }

    await appDatabase.customStatement(
      'UPDATE servers SET subscription_position = ('
      'SELECT COUNT(*) FROM servers s2 '
      'WHERE s2.subscription_id = servers.subscription_id AND s2.id < servers.id'
      ') WHERE subscription_id IS NOT NULL AND subscription_position IS NULL',
    );

    final tables = await appDatabase
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'favorite_servers'",
        )
        .get();
    if (tables.isEmpty) {
      await m.createTable(appDatabase.favoriteServers);
    }

    final groupTables = await appDatabase
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'server_groups'")
        .get();
    if (groupTables.isEmpty) {
      await m.createTable(appDatabase.serverGroups);
    }
  }
}
