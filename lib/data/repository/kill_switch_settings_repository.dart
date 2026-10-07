import 'package:trusttunnel/data/datasources/kill_switch_settings_datasource.dart';

abstract class KillSwitchSettingsRepository {
  Future<bool> isEnabled();

  Future<void> enable();

  Future<void> disable();
}

class KillSwitchSettingsRepositoryImpl implements KillSwitchSettingsRepository {
  final KillSwitchSettingsDataSource _dataSource;

  KillSwitchSettingsRepositoryImpl({
    required KillSwitchSettingsDataSource dataSource,
  }) : _dataSource = dataSource;

  @override
  Future<bool> isEnabled() => _dataSource.isEnabled();

  @override
  Future<void> enable() => _dataSource.setEnabled(true);

  @override
  Future<void> disable() => _dataSource.setEnabled(false);
}
