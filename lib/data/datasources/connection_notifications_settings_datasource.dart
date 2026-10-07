abstract class ConnectionNotificationsSettingsDataSource {
  Future<bool> isEnabled();

  Future<void> setEnabled(bool enabled);
}
