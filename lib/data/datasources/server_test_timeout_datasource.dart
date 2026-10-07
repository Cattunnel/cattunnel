abstract class ServerTestTimeoutDataSource {
  Future<int> getValueSeconds();

  Future<void> setValueSeconds(int seconds);
}
