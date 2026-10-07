import 'package:trusttunnel/data/datasources/ru_services_settings_datasource.dart';

abstract class RuServicesSettingsRepository {
  Future<bool> isEnabled();

  Future<void> enable();

  Future<void> disable();

  Future<List<String>> getRules();

  Future<void> setRules(List<String> rules);
}

class RuServicesSettingsRepositoryImpl implements RuServicesSettingsRepository {
  final RuServicesSettingsDataSource _dataSource;

  RuServicesSettingsRepositoryImpl({
    required RuServicesSettingsDataSource dataSource,
  }) : _dataSource = dataSource;

  @override
  Future<bool> isEnabled() => _dataSource.isEnabled();

  @override
  Future<void> enable() => _dataSource.setEnabled(true);

  @override
  Future<void> disable() => _dataSource.setEnabled(false);

  @override
  Future<List<String>> getRules() => _dataSource.getRules();

  @override
  Future<void> setRules(List<String> rules) => _dataSource.setRules(rules);
}
