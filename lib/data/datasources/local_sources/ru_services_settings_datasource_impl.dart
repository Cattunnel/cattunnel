import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/data/datasources/ru_services_settings_datasource.dart';

class RuServicesSettingsDataSourceImpl implements RuServicesSettingsDataSource {
  static const _enabledKey = 'ru_services_bypass_enabled';
  static const _rulesKey = 'ru_services_bypass_rules';
  static const _defaultRulesAsset = 'assets/routing_presets/ru_services.txt';

  final SharedPreferences _preferences;

  RuServicesSettingsDataSourceImpl({
    required SharedPreferences preferences,
  }) : _preferences = preferences;

  @override
  Future<bool> isEnabled() async => _preferences.getBool(_enabledKey) ?? true;

  @override
  Future<void> setEnabled(bool enabled) => _preferences.setBool(_enabledKey, enabled);

  @override
  Future<List<String>> getRules() async {
    final stored = _preferences.getStringList(_rulesKey);
    if (stored != null) {
      return stored;
    }

    final defaultText = await rootBundle.loadString(_defaultRulesAsset);

    return defaultText.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
  }

  @override
  Future<void> setRules(List<String> rules) => _preferences.setStringList(_rulesKey, rules);
}
