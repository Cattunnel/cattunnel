import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/feature/updates/domain/update_service.dart';

void main() {
  for (final name in ['cattunnel-update.apk', 'CatTunnel-Setup.exe']) {
    test('$name is kept only when newer and less than an hour old', () async {
      final temp = Directory('evidence').createTempSync('update-cache-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final dir = Directory('${temp.path}/updates')..createSync();
      final file = File('${dir.path}/$name')..writeAsStringSync('installer');
      final now = DateTime(2026, 11, 14, 15);
      file.setLastModifiedSync(now.subtract(const Duration(minutes: 59)));
      File('${dir.path}/build.json').writeAsStringSync(jsonEncode({'build': 2051}));
      await UpdateService.cleanupCache(temporaryDirectory: temp, installedBuild: 2050, now: now);
      expect(file.existsSync(), isTrue);
      await UpdateService.cleanupCache(temporaryDirectory: temp, installedBuild: 2051, now: now);
      expect(dir.existsSync(), isFalse);
      dir.createSync();
      file.writeAsStringSync('installer');
      file.setLastModifiedSync(now.subtract(const Duration(hours: 1)));
      File('${dir.path}/build.json').writeAsStringSync(jsonEncode({'build': 2052}));
      await UpdateService.cleanupCache(temporaryDirectory: temp, installedBuild: 2051, now: now);
      expect(dir.existsSync(), isFalse);
    });
  }
  test('cleanup preserves a fresh shared archive and ignores unrelated ZIPs', () async {
    final temp = Directory('evidence').createTempSync('shared-cache-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final now = DateTime(2026, 11, 14, 15);
    final fresh = File('${temp.path}/trusttunnel_windows_logs_20261114T145900.zip')..writeAsStringSync('fresh');
    final old = File('${temp.path}/trusttunnel_linux_logs_20261113T145900.zip')..writeAsStringSync('old');
    final user = File('${temp.path}/user.zip')..writeAsStringSync('keep');
    fresh.setLastModifiedSync(now.subtract(const Duration(minutes: 1)));
    old.setLastModifiedSync(now.subtract(const Duration(days: 1)));
    await UpdateService.cleanupSharedArchives(temp, now: now);
    expect(fresh.existsSync(), isTrue);
    expect(old.existsSync(), isFalse);
    expect(user.existsSync(), isTrue);
  });
}
