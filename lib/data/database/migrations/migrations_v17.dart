import 'package:drift/drift.dart';
import 'package:trusttunnel/data/database/app_database.dart' as db;
import 'package:trusttunnel/data/database/migrations/migrations.dart';

/// The NineLives key the subscription sent and the local switch that decides
/// whether the engine gets it (ServerData.xhttpServerKey and
/// ServerData.xhttpEncryptionEnabled).
class MigrationsV17 implements Migrations {
  const MigrationsV17();

  @override
  Future<void> migrate(GeneratedDatabase database, Migrator m) async {
    final appDatabase = database as db.AppDatabase;

    final columns = await appDatabase.customSelect('PRAGMA table_info(servers)').get();
    final names = columns.map((row) => row.read<String>('name')).toSet();

    final additions = <String, void Function()>{
      'xhttp_server_key': () => m.addColumn(appDatabase.servers, appDatabase.servers.xhttpServerKey),
      'xhttp_encryption_enabled': () => m.addColumn(appDatabase.servers, appDatabase.servers.xhttpEncryptionEnabled),
    };

    for (final entry in additions.entries) {
      if (names.contains(entry.key)) continue;
      entry.value();
    }
  }
}
