import 'package:trusttunnel/data/datasources/connection_notifications_settings_datasource.dart';

abstract class ConnectionNotificationsSettingsRepository {
  Future<bool> isEnabled();

  Future<void> enable();

  Future<void> disable();
}

class ConnectionNotificationsSettingsRepositoryImpl implements ConnectionNotificationsSettingsRepository {
  final ConnectionNotificationsSettingsDataSource _dataSource;

  ConnectionNotificationsSettingsRepositoryImpl({
    required ConnectionNotificationsSettingsDataSource dataSource,
  }) : _dataSource = dataSource;

  @override
  Future<bool> isEnabled() => _dataSource.isEnabled();

  @override
  Future<void> enable() => _dataSource.setEnabled(true);

  @override
  Future<void> disable() => _dataSource.setEnabled(false);
}
