import 'package:drift/drift.dart';
import 'package:trusttunnel/data/database/app_database.dart' as db;
import 'package:trusttunnel/data/database/migrations/migrations.dart';

/// servers.client_random_auth_key - the TLS auth key, see
/// ServerData.tlsAuthKey.
class MigrationsV13 implements Migrations {
  const MigrationsV13();

  @override
  Future<void> migrate(GeneratedDatabase database, Migrator m) async {
    final appDatabase = database as db.AppDatabase;

    final columns = await appDatabase.customSelect('PRAGMA table_info(servers)').get();
    if (columns.any((row) => row.read<String>('name') == 'client_random_auth_key')) {
      return;
    }

    await m.addColumn(appDatabase.servers, appDatabase.servers.clientRandomAuthKey);
  }
}
