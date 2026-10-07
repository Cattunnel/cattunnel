import 'package:drift/drift.dart';
import 'package:trusttunnel/data/database/app_database.dart' as db;
import 'package:trusttunnel/data/database/migrations/migrations.dart';

/// servers.ru_exit - a key with a Russian exit, for people abroad (only
/// Russian apps go through it).
class MigrationsV8 implements Migrations {
  const MigrationsV8();

  @override
  Future<void> migrate(GeneratedDatabase database, Migrator m) async {
    final appDatabase = database as db.AppDatabase;

    final columns = await appDatabase.customSelect('PRAGMA table_info(servers)').get();
    if (columns.any((row) => row.read<String>('name') == 'ru_exit')) {
      return;
    }

    await m.addColumn(appDatabase.servers, appDatabase.servers.ruExit);
  }
}
