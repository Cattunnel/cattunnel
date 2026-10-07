import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/common/localization/locale_type.dart';

/// The in-app language override (Settings -> Language), stored in
/// SharedPreferences. [LocaleType.system] means "follow the device".
///
/// [App] listens to [current] and rebuilds its `MaterialApp` with the new
/// locale, so a change applies immediately without a restart.
abstract final class AppLocalePreferences {
  static const _key = 'app_locale';

  /// Only the languages this fork actually has translations for.
  static const choices = [LocaleType.system, LocaleType.en, LocaleType.ru];

  static final current = ValueNotifier<LocaleType>(LocaleType.system);

  static void load(SharedPreferences preferences) {
    final stored = preferences.getString(_key);
    current.value = choices.firstWhere((type) => type.name == stored, orElse: () => LocaleType.system);
  }

  static Future<void> set(SharedPreferences preferences, LocaleType type) async {
    current.value = type;
    await preferences.setString(_key, type.name);
  }
}
