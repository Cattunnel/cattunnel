import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:trusttunnel/data/database/db_key_store.dart';
import 'package:trusttunnel/data/database/interceptors/db_log_interceptor.dart';
import 'package:trusttunnel/data/database/secret_column.dart';

Future<File> get databaseFile async {
  final dbFolder = await _getDbContainmentFolder();
  final file = File(p.join(dbFolder.path, 'vpn_oss_db.sqlite'));

  return file;
}

/// Obtains a database connection for running drift in a Dart VM.
DatabaseConnection connect() => DatabaseConnection.delayed(
  Future(() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();

      final cacheBase = (await getTemporaryDirectory()).path;

      // We can't access /tmp on Android, which sqlite3 would try by default.
      // Explicitly tell it about the correct temporary directory.
      sqlite3.tempDirectory = cacheBase;
    }

    final file = await databaseFile;
    // The key of the secret columns, before the first query (migration v14
    // seals what older versions left in plain text).
    if (!SecretColumn.ready) {
      SecretColumn.useKey(await DbKeyStore.load(File('${file.path}.key')));
    }

    final connection = NativeDatabase.createBackgroundConnection(file);

    return connection.interceptWith(DBLogInterceptor());
  }),
);

Future<Directory> _getDbContainmentFolder() async {
  final Directory path;
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS || TargetPlatform.macOS:
      path = await getLibraryDirectory();
    case TargetPlatform.windows:
      path = await getApplicationSupportDirectory();
    default:
      path = await getApplicationDocumentsDirectory();
  }
  if (!await path.exists()) {
    await path.create();
  }

  return path;
}
