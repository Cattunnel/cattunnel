import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/data/datasources/server_sort_preference_datasource.dart';
import 'package:trusttunnel/data/model/server_sort_option.dart';

class ServerSortPreferenceDataSourceImpl implements ServerSortPreferenceDataSource {
  static const _key = 'server_sort_option';

  final SharedPreferences _preferences;

  ServerSortPreferenceDataSourceImpl({
    required SharedPreferences preferences,
  }) : _preferences = preferences;

  @override
  Future<ServerSortOption> getValue() async {
    final stored = _preferences.getString(_key);

    return ServerSortOption.values.firstWhere(
      (option) => option.name == stored,
      orElse: () => ServerSortOption.origin,
    );
  }

  @override
  Future<void> setValue(ServerSortOption option) => _preferences.setString(_key, option.name);
}
