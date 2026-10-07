import 'package:trusttunnel/data/datasources/server_test_timeout_datasource.dart';

abstract class ServerTestTimeoutRepository {
  Future<int> getValueSeconds();

  Future<void> setValueSeconds(int seconds);
}

class ServerTestTimeoutRepositoryImpl implements ServerTestTimeoutRepository {
  final ServerTestTimeoutDataSource _dataSource;

  ServerTestTimeoutRepositoryImpl({
    required ServerTestTimeoutDataSource dataSource,
  }) : _dataSource = dataSource;

  @override
  Future<int> getValueSeconds() => _dataSource.getValueSeconds();

  @override
  Future<void> setValueSeconds(int seconds) => _dataSource.setValueSeconds(seconds);
}
