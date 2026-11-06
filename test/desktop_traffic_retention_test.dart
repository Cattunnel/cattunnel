import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/feature/traffic/desktop_traffic_recorder.dart';
import 'package:trusttunnel/feature/traffic/traffic_collection_preferences.dart';
import 'package:trusttunnel/feature/traffic/traffic_data.dart';

void main() {
  late Directory directory;
  late DesktopTrafficRecorder recorder;
  late SharedPreferences prefs;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    directory = await Directory('qa').createTemp('traffic-retention-');
    recorder = DesktopTrafficRecorder.forTesting(directory);
    await File('${directory.path}/traffic_hourly.tsv').writeAsString('3600\t1\t12\t34\n');
    await File('${directory.path}/traffic_pending.tsv').writeAsString('7200\t1\t56\t78\n');
  });
  tearDown(() async {
    recorder.dispose();
    debugDefaultTargetPlatformOverride = null;
    await directory.delete(recursive: true);
  });
  test('turning off preserves files and enabling early cancels deletion', () async {
    final before = await recorder.read();
    await recorder.setCollection(prefs, false);
    expect(await recorder.read(), before);
    await recorder.setCollection(prefs, true);
    expect(await recorder.read(), before);
    expect(prefs.containsKey(TrafficCollectionPreferences.deleteAtKey), isFalse);
  });
  test('expired data is erased before enabling even if there was no timer', () async {
    await recorder.setCollection(prefs, false);
    await prefs.setInt(TrafficCollectionPreferences.deleteAtKey, 1);
    await recorder.setCollection(prefs, true);
    expect(await recorder.read(), isEmpty);
    expect(directory.listSync(), isEmpty);
  });
  test('explicit clear erases immediately including interrupted temp writes', () async {
    await recorder.setCollection(prefs, false);
    await File('${directory.path}/traffic_hourly.tsv.tmp').writeAsString('partial');
    await recorder.clear();
    expect(await recorder.read(), isEmpty);
    expect(directory.listSync(), isEmpty);
  });
  test('disabled intervals write no rows; resume and the last stop interval count correctly', () async {
    await recorder.clear();
    var rx = 100;
    recorder = DesktopTrafficRecorder.forTesting(directory, readCounters: () => (rx, 0));
    recorder.onState(VpnState.connected, '1');
    await recorder.sampleForTesting();
    rx = 150;
    await recorder.sampleForTesting();
    final before = await recorder.read();
    expect(TrafficSource.parse(before).fold<int>(0, (sum, row) => sum + row.total), 50);
    await recorder.setCollection(prefs, false);
    rx = 1000;
    await recorder.sampleForTesting();
    expect(await recorder.read(), before);
    await recorder.setCollection(prefs, true);
    await recorder.sampleForTesting();
    rx = 1050;
    await recorder.sampleForTesting();
    rx = 1100;
    recorder.onState(VpnState.disconnected, '1');
    await recorder.read();
    final total = TrafficSource.parse(await recorder.read()).fold<int>(0, (sum, row) => sum + row.total);
    expect(total, 150);
  });
}
