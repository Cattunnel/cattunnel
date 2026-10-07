import 'package:drift/drift.dart';
import 'package:trusttunnel/data/database/app_database.dart' as db;
import 'package:trusttunnel/data/database/migrations/migrations.dart';

/// servers.anti_dpi_desync - the custom anti-DPI split, see
/// ServerData.antiDpiDesync; servers.h2_padding_frames, see
/// ServerData.h2PaddingFrames.
class MigrationsV11 implements Migrations {
  const MigrationsV11();

  @override
  Future<void> migrate(GeneratedDatabase database, Migrator m) async {
    final appDatabase = database as db.AppDatabase;

    final columns = await appDatabase.customSelect('PRAGMA table_info(servers)').get();
    final names = columns.map((row) => row.read<String>('name')).toSet();
    if (!names.contains('anti_dpi_desync')) {
      await m.addColumn(appDatabase.servers, appDatabase.servers.antiDpiDesync);
    }
    if (!names.contains('h2_padding_frames')) {
      await m.addColumn(appDatabase.servers, appDatabase.servers.h2PaddingFrames);
    }
  }
}
