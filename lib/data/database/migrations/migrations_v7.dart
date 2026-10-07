import 'package:drift/drift.dart';
import 'package:trusttunnel/data/database/app_database.dart' as db;
import 'package:trusttunnel/data/database/migrations/migrations.dart';

class MigrationsV7 implements Migrations {
  const MigrationsV7();

  @override
  Future<void> migrate(GeneratedDatabase database, Migrator m) async {
    final appDatabase = database as db.AppDatabase;

    // Same guard as MigrationsV6: a table created by an earlier step from the
    // current definition already has the column.
    final columns = await appDatabase.customSelect('PRAGMA table_info(servers)').get();
    if (columns.any((row) => row.read<String>('name') == 'anti_dpi')) {
      return;
    }

    await m.addColumn(appDatabase.servers, appDatabase.servers.antiDpi);
  }
}
