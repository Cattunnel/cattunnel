import 'package:drift/drift.dart';
import 'package:trusttunnel/data/database/app_database.dart' as db;
import 'package:trusttunnel/data/database/migrations/migrations.dart';

/// servers.anti_dpi_mode - which anti-DPI technique (DPI2), see
/// ServerData.antiDpiMode.
class MigrationsV9 implements Migrations {
  const MigrationsV9();

  @override
  Future<void> migrate(GeneratedDatabase database, Migrator m) async {
    final appDatabase = database as db.AppDatabase;

    final columns = await appDatabase.customSelect('PRAGMA table_info(servers)').get();
    if (columns.any((row) => row.read<String>('name') == 'anti_dpi_mode')) {
      return;
    }

    await m.addColumn(appDatabase.servers, appDatabase.servers.antiDpiMode);
  }
}
