import 'package:shared_preferences/shared_preferences.dart';

enum WindowCloseAction { ask, tray, exit }

abstract final class WindowClosePreferences {
  static const _key = 'window_close_action';

  static WindowCloseAction read(SharedPreferences prefs) => switch (prefs.getString(_key)) {
    'tray' => WindowCloseAction.tray,
    'exit' => WindowCloseAction.exit,
    _ => WindowCloseAction.ask,
  };

  static Future<void> write(SharedPreferences prefs, WindowCloseAction value) async {
    await prefs.setString(_key, value.name);
  }
}

WindowCloseAction resolveWindowClose({
  required WindowCloseAction preference,
  required bool hasTray,
  required bool vpnActive,
}) {
  if (!hasTray) return vpnActive ? WindowCloseAction.ask : WindowCloseAction.exit;
  return preference;
}
