import 'package:trusttunnel/data/datasources/mtu_settings_datasource.dart';

abstract class MtuSettingsRepository {
  Future<int> getValue();

  Future<void> setValue(int mtu);
}

class MtuSettingsRepositoryImpl implements MtuSettingsRepository {
  final MtuSettingsDataSource _dataSource;

  MtuSettingsRepositoryImpl({
    required MtuSettingsDataSource dataSource,
  }) : _dataSource = dataSource;

  @override
  Future<int> getValue() => _dataSource.getValue();

  @override
  Future<void> setValue(int mtu) => _dataSource.setValue(mtu);
}
