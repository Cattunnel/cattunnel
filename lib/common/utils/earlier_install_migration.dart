import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// First start of this build on Windows or Linux, when an earlier CatTunnel
/// build with another publisher id (another Windows CompanyName / Linux
/// application id) left its data next to ours: copy it over, so servers,
/// subscriptions and settings carry over to this build.
///
/// - Windows keeps everything (database, preferences, lists, logs) in
///   `%APPDATA%\<company>\CatTunnel`; an earlier build is any
///   `%APPDATA%\<other company>\CatTunnel`.
/// - Linux keeps preferences and lists in `~/.local/share/<application id>`
///   (the database is in ~/Documents and is shared anyway); an earlier build is
///   any `~/.local/share/<other id ending in .cattunnel>`.
///
/// Copies, never moves or overwrites: the earlier install stays intact. Runs
/// once (a marker file), and only while this build has no data of its own.
Future<void> migrateFromEarlierInstall() async {
  if (kIsWeb || !(Platform.isWindows || Platform.isLinux)) return;
  try {
    await migrateFromEarlierInstallIn(await getApplicationSupportDirectory(), windows: Platform.isWindows);
  } catch (e) {
    debugPrint('earlier install migration skipped: $e');
  }
}

const _marker = '.earlier-install-checked';
const _ownData = ['shared_preferences.json', 'vpn_oss_db.sqlite'];

/// [target] is this build's support directory. Returns the directory data was
/// copied from, or null.
@visibleForTesting
Future<Directory?> migrateFromEarlierInstallIn(Directory target, {required bool windows}) async {
  final marker = File(p.join(target.path, _marker));
  if (await marker.exists()) return null;

  Directory? source;
  if (!await _hasData(target)) {
    source = await _findEarlier(target, windows: windows);
    if (source != null) await _copyMissing(source, target);
  }
  await target.create(recursive: true);
  await marker.writeAsString(source == null ? 'none\n' : '${source.path}\n');

  return source;
}

Future<bool> _hasData(Directory dir) async {
  for (final name in _ownData) {
    if (await File(p.join(dir.path, name)).exists()) return true;
  }

  return false;
}

Future<Directory?> _findEarlier(Directory target, {required bool windows}) async {
  // Windows: %APPDATA%\<company>\CatTunnel -> look at %APPDATA%\*\CatTunnel.
  // Linux: ~/.local/share/<id> -> look at ~/.local/share/*.cattunnel.
  final root = windows ? target.parent.parent : target.parent;
  if (!await root.exists()) return null;
  final productName = p.basename(target.path);

  final candidates = <Directory>[];
  await for (final entry in root.list(followLinks: false)) {
    if (entry is! Directory) continue;
    final dir = windows ? Directory(p.join(entry.path, productName)) : entry;
    if (p.equals(dir.path, target.path)) continue;
    if (!windows && !p.basename(dir.path).toLowerCase().endsWith('.cattunnel')) continue;
    if (await dir.exists() && await _hasData(dir)) candidates.add(dir);
  }
  if (candidates.isEmpty) return null;

  // Several earlier installs: the one used last.
  final stamped = <(Directory, DateTime)>[];
  for (final dir in candidates) {
    stamped.add((dir, (await dir.stat()).modified));
  }
  stamped.sort((a, b) => b.$2.compareTo(a.$2));

  return stamped.first.$1;
}

Future<void> _copyMissing(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final entry in from.list(recursive: true, followLinks: false)) {
    final relative = p.relative(entry.path, from: from.path);
    final destination = p.join(to.path, relative);
    if (entry is Directory) {
      await Directory(destination).create(recursive: true);
    } else if (entry is File && !await File(destination).exists()) {
      await File(destination).parent.create(recursive: true);
      await entry.copy(destination);
    }
  }
}
