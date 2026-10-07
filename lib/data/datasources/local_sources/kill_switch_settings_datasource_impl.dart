import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/data/datasources/kill_switch_settings_datasource.dart';

class KillSwitchSettingsDataSourceImpl implements KillSwitchSettingsDataSource {
  static const _enabledKey = 'kill_switch_enabled';

  final SharedPreferences _preferences;

  KillSwitchSettingsDataSourceImpl({
    required SharedPreferences preferences,
  }) : _preferences = preferences;

  // Matches the VPN backend's own default (see Configuration.killSwitchEnabled),
  // so a user who never opens this setting keeps the backend's default behavior.
  @override
  Future<bool> isEnabled() async => _preferences.getBool(_enabledKey) ?? true;

  @override
  Future<void> setEnabled(bool enabled) => _preferences.setBool(_enabledKey, enabled);
}
