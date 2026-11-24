import 'package:drift/drift.dart';
import 'package:trusttunnel/data/database/app_database.dart' as db;
import 'package:trusttunnel/data/database/migrations/migrations.dart';

/// Ready SNI names of a server without its main one (subscription tag 0x52,
/// ServerData.sniPool), stored as a JSON array.
class MigrationsV18 implements Migrations {
  const MigrationsV18();

  @override
  Future<void> migrate(GeneratedDatabase database, Migrator m) async {
    final appDatabase = database as db.AppDatabase;

    final columns = await appDatabase.customSelect('PRAGMA table_info(servers)').get();
    final names = columns.map((row) => row.read<String>('name')).toSet();

    if (names.contains('sni_pool')) return;
    await m.addColumn(appDatabase.servers, appDatabase.servers.sniPool);
  }
}
