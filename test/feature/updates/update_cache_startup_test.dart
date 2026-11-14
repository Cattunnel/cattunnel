import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:trusttunnel/feature/updates/widgets/update_watcher.dart';

class _Paths extends PathProviderPlatform {
  final String path;
  _Paths(this.path);
  @override
  Future<String> getTemporaryPath() async => path;
}

void main() {
  testWidgets('startup removes legacy installer and stale shared log archives', (tester) async {
    final temp = Directory('evidence').createTempSync('cache-startup-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.absolute.path);
    addTearDown(() => PathProviderPlatform.instance = previous);
    PackageInfo.setMockInitialValues(
      appName: 'CatTunnel',
      packageName: 'test',
      version: '1.5.8',
      buildNumber: '2050',
      buildSignature: '',
    );
    final updates = Directory('${temp.path}/updates')..createSync();
    final installer = File('${updates.path}/cattunnel-update.apk')..writeAsStringSync('legacy');
    final logs = File('${temp.path}/trusttunnel_android_logs_20261113T010000.zip')..writeAsStringSync('old logs');
    logs.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));
    final unrelated = File('${temp.path}/user.zip')..writeAsStringSync('keep');
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: UpdateWatcher(child: SizedBox())));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(installer.existsSync(), isFalse);
      expect(logs.existsSync(), isFalse);
      expect(unrelated.existsSync(), isTrue);
    });
    await tester.pumpWidget(const SizedBox());
  });
}
