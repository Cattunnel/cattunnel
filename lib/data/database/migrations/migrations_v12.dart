import 'package:drift/drift.dart';
import 'package:trusttunnel/data/database/app_database.dart' as db;
import 'package:trusttunnel/data/database/migrations/migrations.dart';

/// servers.block_quic - QUIC off, see ServerData.blockQuic.
class MigrationsV12 implements Migrations {
  const MigrationsV12();

  @override
  Future<void> migrate(GeneratedDatabase database, Migrator m) async {
    final appDatabase = database as db.AppDatabase;

    final columns = await appDatabase.customSelect('PRAGMA table_info(servers)').get();
    final names = columns.map((row) => row.read<String>('name')).toSet();
    if (!names.contains('block_quic')) {
      await m.addColumn(appDatabase.servers, appDatabase.servers.blockQuic);
    }
  }
}
