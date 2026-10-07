import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/data/datasources/connection_notifications_settings_datasource.dart';

class ConnectionNotificationsSettingsDataSourceImpl implements ConnectionNotificationsSettingsDataSource {
  static const _enabledKey = 'connection_notifications_enabled';

  final SharedPreferences _preferences;

  ConnectionNotificationsSettingsDataSourceImpl({
    required SharedPreferences preferences,
  }) : _preferences = preferences;

  @override
  Future<bool> isEnabled() async => _preferences.getBool(_enabledKey) ?? true;

  @override
  Future<void> setEnabled(bool enabled) => _preferences.setBool(_enabledKey, enabled);
}
