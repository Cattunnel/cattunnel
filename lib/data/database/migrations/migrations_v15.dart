import 'package:drift/drift.dart';
import 'package:trusttunnel/data/database/app_database.dart' as db;
import 'package:trusttunnel/data/database/migrations/migrations.dart';

/// The settings of the traffic shaper (the padding), the keepalive and the
/// XHTTP transport - see ServerData.h2PaddingFramesMin, ServerData.keepaliveIntervalSecs
/// and ServerData.xhttpEnabled.
class MigrationsV15 implements Migrations {
  const MigrationsV15();

  @override
  Future<void> migrate(GeneratedDatabase database, Migrator m) async {
    final appDatabase = database as db.AppDatabase;

    final columns = await appDatabase.customSelect('PRAGMA table_info(servers)').get();
    final names = columns.map((row) => row.read<String>('name')).toSet();

    final additions = <String, void Function()>{
      'h2_padding_frames_min': () => m.addColumn(appDatabase.servers, appDatabase.servers.h2PaddingFramesMin),
      'h2_padding_per_stream': () => m.addColumn(appDatabase.servers, appDatabase.servers.h2PaddingPerStream),
      'h2_padding_min_bytes': () => m.addColumn(appDatabase.servers, appDatabase.servers.h2PaddingMinBytes),
      'h2_padding_max_bytes': () => m.addColumn(appDatabase.servers, appDatabase.servers.h2PaddingMaxBytes),
      'h2_padding_stream_bytes': () => m.addColumn(appDatabase.servers, appDatabase.servers.h2PaddingStreamBytes),
      'h2_padding_session_bytes': () => m.addColumn(appDatabase.servers, appDatabase.servers.h2PaddingSessionBytes),
      'keepalive_interval_secs': () => m.addColumn(appDatabase.servers, appDatabase.servers.keepaliveIntervalSecs),
      'keepalive_signal': () => m.addColumn(appDatabase.servers, appDatabase.servers.keepaliveSignal),
      'session_lifetime_secs': () => m.addColumn(appDatabase.servers, appDatabase.servers.sessionLifetimeSecs),
      'xhttp_enabled': () => m.addColumn(appDatabase.servers, appDatabase.servers.xhttpEnabled),
      'xhttp_path': () => m.addColumn(appDatabase.servers, appDatabase.servers.xhttpPath),
    };

    for (final entry in additions.entries) {
      if (names.contains(entry.key)) continue;
      entry.value();
    }
  }
}
