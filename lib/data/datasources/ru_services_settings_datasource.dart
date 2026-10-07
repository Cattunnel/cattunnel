abstract class RuServicesSettingsDataSource {
  Future<bool> isEnabled();

  Future<void> setEnabled(bool enabled);

  Future<List<String>> getRules();

  Future<void> setRules(List<String> rules);
}
