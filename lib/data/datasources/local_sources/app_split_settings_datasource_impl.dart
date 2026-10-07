import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/data/datasources/app_split_settings_datasource.dart';

class AppSplitSettingsDataSourceImpl implements AppSplitSettingsDataSource {
  static const _modeKey = 'app_split_mode';
  static const _appsKeyPrefix = 'app_split_apps_';
  static const _autoRuCnKey = 'app_split_auto_ru_cn';
  static const _forcedVpnKey = 'app_split_forced_vpn';

  final SharedPreferences _preferences;

  AppSplitSettingsDataSourceImpl({
    required SharedPreferences preferences,
  }) : _preferences = preferences;

  @override
  Future<AppSplitMode> getMode() async {
    final name = _preferences.getString(_modeKey);

    return AppSplitMode.values.firstWhere((mode) => mode.name == name, orElse: () => AppSplitMode.off);
  }

  @override
  Future<void> setMode(AppSplitMode mode) => _preferences.setString(_modeKey, mode.name);

  @override
  Future<List<String>> getApps(AppSplitMode mode) async =>
      mode == AppSplitMode.off ? const [] : _preferences.getStringList('$_appsKeyPrefix${mode.name}') ?? const [];

  @override
  Future<void> setApps(AppSplitMode mode, List<String> packages) async {
    if (mode == AppSplitMode.off) return;
    await _preferences.setStringList('$_appsKeyPrefix${mode.name}', packages);
  }

  @override
  Future<bool> getAutoRuCn() async => _preferences.getBool(_autoRuCnKey) ?? true;

  @override
  Future<void> setAutoRuCn(bool enabled) => _preferences.setBool(_autoRuCnKey, enabled);

  @override
  Future<List<String>> getForcedVpn() async => _preferences.getStringList(_forcedVpnKey) ?? const [];

  @override
  Future<void> setForcedVpn(List<String> packages) => _preferences.setStringList(_forcedVpnKey, packages);
}
