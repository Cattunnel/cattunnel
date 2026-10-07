import 'package:drift/drift.dart';
import 'package:trusttunnel/data/database/app_database.dart' as db;
import 'package:trusttunnel/data/database/migrations/migrations.dart';

/// servers.tls_profile - the ClientHello fingerprint, see
/// ServerData.tlsProfile.
class MigrationsV10 implements Migrations {
  const MigrationsV10();

  @override
  Future<void> migrate(GeneratedDatabase database, Migrator m) async {
    final appDatabase = database as db.AppDatabase;

    final columns = await appDatabase.customSelect('PRAGMA table_info(servers)').get();
    if (columns.any((row) => row.read<String>('name') == 'tls_profile')) {
      return;
    }

    await m.addColumn(appDatabase.servers, appDatabase.servers.tlsProfile);
  }
}
