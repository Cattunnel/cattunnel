import 'package:trusttunnel/data/datasources/server_sort_preference_datasource.dart';
import 'package:trusttunnel/data/model/server_sort_option.dart';

abstract class ServerSortPreferenceRepository {
  Future<ServerSortOption> getValue();

  Future<void> setValue(ServerSortOption option);
}

class ServerSortPreferenceRepositoryImpl implements ServerSortPreferenceRepository {
  final ServerSortPreferenceDataSource _dataSource;

  ServerSortPreferenceRepositoryImpl({
    required ServerSortPreferenceDataSource dataSource,
  }) : _dataSource = dataSource;

  @override
  Future<ServerSortOption> getValue() => _dataSource.getValue();

  @override
  Future<void> setValue(ServerSortOption option) => _dataSource.setValue(option);
}
