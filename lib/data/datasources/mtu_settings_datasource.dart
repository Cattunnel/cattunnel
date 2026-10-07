abstract class MtuSettingsDataSource {
  Future<int> getValue();

  Future<void> setValue(int mtu);
}
