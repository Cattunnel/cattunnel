import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/data/datasources/mtu_settings_datasource.dart';

class MtuSettingsDataSourceImpl implements MtuSettingsDataSource {
  static const _valueKey = 'mtu_size';

  // Matches Tun's own default (see plugins/vpn_plugin/lib/models/tun.dart)
  // and the backend's own INI-decode default (IniConst.defaultTunMtu), so a
  // user who never opens this setting keeps the backend's default behavior.
  static const defaultValue = 1500;

  final SharedPreferences _preferences;

  MtuSettingsDataSourceImpl({
    required SharedPreferences preferences,
  }) : _preferences = preferences;

  @override
  Future<int> getValue() async => _preferences.getInt(_valueKey) ?? defaultValue;

  @override
  Future<void> setValue(int mtu) => _preferences.setInt(_valueKey, mtu);
}
