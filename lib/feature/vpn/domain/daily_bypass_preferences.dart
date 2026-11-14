import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/data/model/server_data.dart';

abstract final class DailyBypassPreferences {
  static const untilKey = 'automatic_bypass_until';
  static DateTime midnightAfter(DateTime at) => DateTime(at.year, at.month, at.day + 1);
  static bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  static bool enabled(SharedPreferences preferences, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final until = preferences.getInt(untilKey);
    return until != null && until > at.millisecondsSinceEpoch && until <= midnightAfter(at).millisecondsSinceEpoch;
  }

  static Future<void> setEnabled(SharedPreferences preferences, bool value, {DateTime? now}) async {
    if (value) {
      await preferences.setInt(untilKey, midnightAfter(now ?? DateTime.now()).millisecondsSinceEpoch);
    } else {
      await preferences.remove(untilKey);
    }
  }

  static bool automaticFor(ServerData data, SharedPreferences preferences, {DateTime? now}) {
    if (data.subscriptionOverride || data.antiDpi) {
      return data.antiDpi && data.antiDpiMode == ServerData.antiDpiAuto;
    }
    return enabled(preferences, now: now);
  }
}
