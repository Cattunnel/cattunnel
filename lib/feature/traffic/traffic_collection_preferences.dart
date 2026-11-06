import 'package:shared_preferences/shared_preferences.dart';

abstract final class TrafficCollectionPreferences {
  static const enabledKey = 'traffic_collection_enabled';
  static const deleteAtKey = 'traffic_collection_delete_at';

  static bool enabled(SharedPreferences prefs) => prefs.getBool(enabledKey) ?? true;

  /// Same local time next calendar month, clamped to that month's last day.
  static DateTime deletionDate(DateTime disabledAt) {
    final lastDay = DateTime(disabledAt.year, disabledAt.month + 2, 0).day;
    return DateTime(
      disabledAt.year,
      disabledAt.month + 1,
      disabledAt.day > lastDay ? lastDay : disabledAt.day,
      disabledAt.hour,
      disabledAt.minute,
      disabledAt.second,
      disabledAt.millisecond,
    );
  }

  static bool deletionDue(SharedPreferences prefs, DateTime now) {
    final deadline = prefs.getInt(deleteAtKey);
    return !enabled(prefs) && deadline != null && now.millisecondsSinceEpoch >= deadline;
  }

  static Future<void> set(SharedPreferences prefs, bool value, {DateTime? now}) async {
    if (enabled(prefs) == value) return;
    if (value) {
      await prefs.remove(deleteAtKey);
    } else {
      await prefs.setInt(deleteAtKey, deletionDate(now ?? DateTime.now()).millisecondsSinceEpoch);
    }
    await prefs.setBool(enabledKey, value);
  }
}
