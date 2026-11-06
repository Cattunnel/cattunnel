import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/feature/traffic/traffic_collection_preferences.dart';
import 'package:trusttunnel/feature/traffic/traffic_data.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('enabled by default; limit is suspended and restored, not erased', () async {
    final prefs = await SharedPreferences.getInstance();
    expect(TrafficCollectionPreferences.enabled(prefs), isTrue);
    await TrafficLimit.set(prefs, 1234);
    final disabled = DateTime(2026, 1, 31, 12);
    await TrafficCollectionPreferences.set(prefs, false, now: disabled);
    expect(TrafficLimit.get(prefs), 0);
    expect(TrafficCollectionPreferences.deletionDue(prefs, DateTime(2026, 2, 28, 11, 59)), isFalse);
    expect(TrafficCollectionPreferences.deletionDue(prefs, DateTime(2026, 2, 28, 12)), isTrue);
    await TrafficCollectionPreferences.set(prefs, true, now: DateTime(2026, 2, 20));
    expect(TrafficLimit.get(prefs), 1234);
    expect(prefs.containsKey(TrafficCollectionPreferences.deleteAtKey), isFalse);
  });
  test('repeated disable does not postpone deletion; leap February is clamped', () async {
    final prefs = await SharedPreferences.getInstance();
    await TrafficCollectionPreferences.set(prefs, false, now: DateTime(2024, 1, 31, 18));
    await TrafficCollectionPreferences.set(prefs, false, now: DateTime(2024, 2, 20));
    expect(
      DateTime.fromMillisecondsSinceEpoch(prefs.getInt(TrafficCollectionPreferences.deleteAtKey)!),
      DateTime(2024, 2, 29, 18),
    );
  });
}
