import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/data/datasources/server_test_timeout_datasource.dart';

class ServerTestTimeoutDataSourceImpl implements ServerTestTimeoutDataSource {
  static const _key = 'server_test_timeout_seconds';
  static const defaultValue = 5;

  final SharedPreferences _preferences;

  ServerTestTimeoutDataSourceImpl({
    required SharedPreferences preferences,
  }) : _preferences = preferences;

  @override
  Future<int> getValueSeconds() async => _preferences.getInt(_key) ?? defaultValue;

  @override
  Future<void> setValueSeconds(int seconds) => _preferences.setInt(_key, seconds);
}
