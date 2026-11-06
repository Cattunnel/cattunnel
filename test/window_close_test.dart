import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/feature/app/controller/window_close_preferences.dart';

void main() {
  test('default asks and remembered choices survive reload', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(WindowClosePreferences.read(prefs), WindowCloseAction.ask);
    for (final choice in WindowCloseAction.values) {
      await WindowClosePreferences.write(prefs, choice);
      await prefs.reload();
      expect(WindowClosePreferences.read(prefs), choice);
      expect(resolveWindowClose(preference: choice, hasTray: true, vpnActive: true), choice);
    }
  });
  test('without tray never hides; active VPN needs confirmation', () {
    for (final choice in WindowCloseAction.values) {
      expect(resolveWindowClose(preference: choice, hasTray: false, vpnActive: true), WindowCloseAction.ask);
      expect(resolveWindowClose(preference: choice, hasTray: false, vpnActive: false), WindowCloseAction.exit);
    }
  });
}
