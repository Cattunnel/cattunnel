import 'package:drift/drift.dart';
import 'package:trusttunnel/data/database/app_database.dart' as db;
import 'package:trusttunnel/data/database/migrations/migrations.dart';
import 'package:trusttunnel/data/database/secret_column.dart';

/// Seals the secret columns (SecretColumn) that an older version wrote as
/// plain text: servers.login/password/client_random_auth_key,
/// subscriptions.url/age_private_key. Already sealed values stay as they are.
class MigrationsV14 implements Migrations {
  const MigrationsV14();

  static const _columns = {
    'servers': ['login', 'password', 'client_random_auth_key'],
    'subscriptions': ['url', 'age_private_key'],
  };

  @override
  Future<void> migrate(GeneratedDatabase database, Migrator m) async {
    final appDatabase = database as db.AppDatabase;
    if (!SecretColumn.ready) return;

    for (final MapEntry(key: table, value: columns) in _columns.entries) {
      final rows = await appDatabase.customSelect('SELECT id, ${columns.join(', ')} FROM $table').get();
      for (final row in rows) {
        final updates = <String, String>{};
        for (final column in columns) {
          final value = row.readNullable<String>(column);
          if (value != null && value.isNotEmpty && !SecretColumn.isSealed(value)) {
            updates[column] = SecretColumn.seal(value);
          }
        }
        if (updates.isEmpty) continue;
        await appDatabase.customStatement(
          'UPDATE $table SET ${updates.keys.map((c) => '$c = ?').join(', ')} WHERE id = ?',
          [...updates.values, row.read<int>('id')],
        );
      }
    }
  }
}
