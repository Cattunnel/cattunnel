import 'package:trusttunnel/data/model/server_sort_option.dart';

abstract class ServerSortPreferenceDataSource {
  Future<ServerSortOption> getValue();

  Future<void> setValue(ServerSortOption option);
}
