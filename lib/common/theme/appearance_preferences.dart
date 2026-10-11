import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «Минимализм» is the original look; «Уютный» adds the big connect button
/// with Marsik on the Servers screen and rounder shapes; «Y2K» is the same
/// home as «Уютный» in an early-2000s look (navy, electric blue, chrome,
/// shards), always dark; «Аэро» is that home again in the Frutiger Aero
/// look (sky, grass, glass, bubbles) that follows the time of day.
enum AppStyle { minimal, cozy, y2k, aero }

/// Settings -> Appearance: the style and light/dark/system theme, stored in
/// SharedPreferences. [App] listens to both and rebuilds its `MaterialApp`,
/// so a change applies immediately (like AppLocalePreferences).
abstract final class AppearancePreferences {
  static const _styleKey = 'appearance_style';
  static const _themeModeKey = 'appearance_theme_mode';

  /// «Уютный» unless the person picked «Минимализм» themselves.
  static final style = ValueNotifier<AppStyle>(AppStyle.cozy);
  static final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

  static void load(SharedPreferences preferences) {
    final storedStyle = preferences.getString(_styleKey);
    style.value = AppStyle.values.firstWhere((value) => value.name == storedStyle, orElse: () => AppStyle.cozy);

    final storedMode = preferences.getString(_themeModeKey);
    themeMode.value = ThemeMode.values.firstWhere(
      (value) => value.name == storedMode,
      orElse: () => ThemeMode.system,
    );
  }

  static Future<void> setStyle(SharedPreferences preferences, AppStyle value) async {
    style.value = value;
    await preferences.setString(_styleKey, value.name);
  }

  static Future<void> setThemeMode(SharedPreferences preferences, ThemeMode value) async {
    themeMode.value = value;
    await preferences.setString(_themeModeKey, value.name);
  }
}
