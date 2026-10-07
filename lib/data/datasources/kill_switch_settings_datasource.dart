abstract class KillSwitchSettingsDataSource {
  Future<bool> isEnabled();

  Future<void> setEnabled(bool enabled);
}
