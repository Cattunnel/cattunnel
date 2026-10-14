import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/datasources/server_datasource.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/repository/deep_link_repository.dart';

// The data source as a subscription refresh sees it: the link's ru_exit as is.
class _RuExitSource implements ServerDataSource {
  static const _server = ServerData.empty(name: 'Москва', ruExit: true);

  @override
  Future<ServerData> getServerByBase64({required String base64, required String routingProfileId}) async => _server;

  @override
  ServerData getServerFromConfig({required String config, required String routingProfileId}) => _server;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final repository = DeepLinkRepositoryImpl(serverDataSource: _RuExitSource());

  test('ru_exit from a tt:// link someone sent is not applied silently', () async {
    final server = await repository.parseDataFromLink(deepLink: 'x');
    expect(server.ruExit, isFalse);
    expect(server.name, 'Москва');
  });

  test('ru_exit from a config file is not applied silently', () {
    expect(repository.parseDataFromConfig(config: 'x').ruExit, isFalse);
  });
}
