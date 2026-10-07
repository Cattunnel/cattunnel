import 'package:drift/drift.dart';
import 'package:trusttunnel/data/database/app_database.dart' as db;
import 'package:trusttunnel/data/database/migrations/migrations.dart';

class MigrationsV6 implements Migrations {
  const MigrationsV6();

  @override
  Future<void> migrate(GeneratedDatabase database, Migrator m) async {
    final appDatabase = database as db.AppDatabase;

    // Coming from v4 or older, MigrationsV5 has just created `subscriptions`
    // from the *current* table definition - which already has this column -
    // so adding it again would fail with "duplicate column name".
    final columns = await appDatabase.customSelect('PRAGMA table_info(subscriptions)').get();
    if (columns.any((row) => row.read<String>('name') == 'age_private_key')) {
      return;
    }

    await m.addColumn(appDatabase.subscriptions, appDatabase.subscriptions.agePrivateKey);
  }
}
