import 'package:trusttunnel/data/datasources/app_split_settings_datasource.dart';

abstract class AppSplitSettingsRepository {
  Future<AppSplitMode> getMode();

  Future<void> setMode(AppSplitMode mode);

  Future<List<String>> getApps(AppSplitMode mode);

  Future<void> setApps(AppSplitMode mode, List<String> packages);

  Future<bool> getAutoRuCn();

  Future<void> setAutoRuCn(bool enabled);

  Future<List<String>> getForcedVpn();

  Future<void> setForcedVpn(List<String> packages);
}

class AppSplitSettingsRepositoryImpl implements AppSplitSettingsRepository {
  final AppSplitSettingsDataSource _dataSource;

  AppSplitSettingsRepositoryImpl({
    required AppSplitSettingsDataSource dataSource,
  }) : _dataSource = dataSource;

  @override
  Future<AppSplitMode> getMode() => _dataSource.getMode();

  @override
  Future<void> setMode(AppSplitMode mode) => _dataSource.setMode(mode);

  @override
  Future<List<String>> getApps(AppSplitMode mode) => _dataSource.getApps(mode);

  @override
  Future<void> setApps(AppSplitMode mode, List<String> packages) => _dataSource.setApps(mode, packages);

  @override
  Future<bool> getAutoRuCn() => _dataSource.getAutoRuCn();

  @override
  Future<void> setAutoRuCn(bool enabled) => _dataSource.setAutoRuCn(enabled);

  @override
  Future<List<String>> getForcedVpn() => _dataSource.getForcedVpn();

  @override
  Future<void> setForcedVpn(List<String> packages) => _dataSource.setForcedVpn(packages);
}
