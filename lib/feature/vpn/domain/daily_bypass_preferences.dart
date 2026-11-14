import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/data/model/server_data.dart';

abstract final class DailyBypassPreferences {
  /// Subscription keys: turned on by hand, it lasts until local midnight.
  static const untilKey = 'automatic_bypass_until';

  /// Personal keys (added by hand, no subscription): stays on (owner 14.11).
  static const personalKey = 'automatic_bypass_personal';
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

  static bool personalEnabled(SharedPreferences preferences) => preferences.getBool(personalKey) ?? false;

  static Future<void> setPersonalEnabled(SharedPreferences preferences, bool value) async {
    if (value) {
      await preferences.setBool(personalKey, true);
    } else {
      await preferences.remove(personalKey);
    }
  }

  /// Who decides about the bypass for this key: the key itself when it is
  /// above the subscription or asks for the bypass; otherwise the switch of
  /// its kind - personal keys the permanent one, subscription keys the daily one.
  static bool automaticFor(ServerData data, SharedPreferences preferences, {DateTime? now}) {
    if (data.subscriptionOverride || data.antiDpi) {
      return data.antiDpi && data.antiDpiMode == ServerData.antiDpiAuto;
    }
    if (data.subscriptionId == null) return personalEnabled(preferences);
    return enabled(preferences, now: now);
  }
}
