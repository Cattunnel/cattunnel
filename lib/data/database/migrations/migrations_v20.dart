import 'package:drift/drift.dart';
import 'package:trusttunnel/data/database/app_database.dart' as db;
import 'package:trusttunnel/data/database/migrations/migrations.dart';

/// 1.5.9.5: the timed rotation between servers of one key (item 9a: the
/// addresses with their SNI pools, the switch, the range of the term) and
/// CatTail (on, ports, key, padding scheme). v19 is the server order and
/// favorites (item 12). Old rows get no rotation and no CatTail.
class MigrationsV20 implements Migrations {
  const MigrationsV20();

  @override
  Future<void> migrate(GeneratedDatabase database, Migrator m) async {
    final appDatabase = database as db.AppDatabase;
    final servers = appDatabase.servers;
    final columns = await appDatabase.customSelect('PRAGMA table_info(servers)').get();
    final names = columns.map((row) => row.read<String>('name')).toSet();

    for (final (name, column) in <(String, GeneratedColumn<Object>)>[
      ('rotation_addresses', servers.rotationAddresses),
      ('rotation_enabled', servers.rotationEnabled),
      ('rotation_min_secs', servers.rotationMinSecs),
      ('rotation_max_secs', servers.rotationMaxSecs),
      ('cattail_enabled', servers.cattailEnabled),
      ('cattail_ports', servers.cattailPorts),
      ('cattail_key', servers.cattailKey),
      ('cattail_pattern', servers.cattailPattern),
    ]) {
      if (!names.contains(name)) await m.addColumn(servers, column);
    }
    await appDatabase.customStatement("UPDATE servers SET tls_profile = '' WHERE tls_profile = 'safari'");
  }
}
