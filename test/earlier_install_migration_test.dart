import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:trusttunnel/common/utils/earlier_install_migration.dart';

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('ct_migration'));
  tearDown(() async => tmp.delete(recursive: true));

  Future<void> write(String path, String text) async {
    final file = File(p.join(tmp.path, path));
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  String read(String path) => File(p.join(tmp.path, path)).readAsStringSync();

  test('Windows: copies %APPDATA%\\<other company>\\CatTunnel into ours', () async {
    await write('Roaming/OldCo/CatTunnel/vpn_oss_db.sqlite', 'db');
    await write('Roaming/OldCo/CatTunnel/shared_preferences.json', '{"a":1}');
    await write('Roaming/OldCo/CatTunnel/ru_lists/compiled.v1', 'lists');
    await write('Roaming/Other/Unrelated/shared_preferences.json', 'x');
    final target = Directory(p.join(tmp.path, 'Roaming/CatTunnel/CatTunnel'));

    final from = await migrateFromEarlierInstallIn(target, windows: true);

    expect(p.basename(from!.parent.path), 'OldCo');
    expect(read('Roaming/CatTunnel/CatTunnel/vpn_oss_db.sqlite'), 'db');
    expect(read('Roaming/CatTunnel/CatTunnel/ru_lists/compiled.v1'), 'lists');
    expect(read('Roaming/OldCo/CatTunnel/vpn_oss_db.sqlite'), 'db'); // the earlier install stays
  });

  test('Linux: copies ~/.local/share/<other id>.cattunnel, not unrelated apps', () async {
    await write('share/org.old.cattunnel/shared_preferences.json', '{"b":2}');
    await write('share/org.someapp/shared_preferences.json', 'no');
    final target = Directory(p.join(tmp.path, 'share/com.cattunnel.app'));

    final from = await migrateFromEarlierInstallIn(target, windows: false);

    expect(p.basename(from!.path), 'org.old.cattunnel');
    expect(read('share/com.cattunnel.app/shared_preferences.json'), '{"b":2}');
  });

  test('own data present: nothing copied, nothing overwritten; runs once', () async {
    await write('share/org.old.cattunnel/shared_preferences.json', 'old');
    await write('share/com.cattunnel.app/shared_preferences.json', 'mine');
    final target = Directory(p.join(tmp.path, 'share/com.cattunnel.app'));

    expect(await migrateFromEarlierInstallIn(target, windows: false), isNull);
    expect(read('share/com.cattunnel.app/shared_preferences.json'), 'mine');

    File(p.join(target.path, 'shared_preferences.json')).deleteSync();
    expect(await migrateFromEarlierInstallIn(target, windows: false), isNull); // marker: checked already
  });
}
