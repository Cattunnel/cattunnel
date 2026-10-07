import 'package:trusttunnel/common/utils/routing_profile_utils.dart';
import 'package:trusttunnel/data/datasources/server_datasource.dart';
import 'package:trusttunnel/data/model/server_data.dart';

abstract class DeepLinkRepository {
  Future<ServerData> parseDataFromLink({
    required String deepLink,
  });

  /// A server from a trusttunnel_client config file (the bot's Linux/PC
  /// config). Throws [FormatException] if it isn't one.
  ServerData parseDataFromConfig({
    required String config,
  });
}

class DeepLinkRepositoryImpl implements DeepLinkRepository {
  final ServerDataSource _serverDataSource;

  const DeepLinkRepositoryImpl({
    required ServerDataSource serverDataSource,
  }) : _serverDataSource = serverDataSource;

  @override
  Future<ServerData> parseDataFromLink({
    required String deepLink,
  }) => _serverDataSource.getServerByBase64(
    base64: deepLink,
    routingProfileId: RoutingProfileUtils.defaultRoutingProfileId,
  );

  @override
  ServerData parseDataFromConfig({
    required String config,
  }) => _serverDataSource.getServerFromConfig(
    config: config,
    routingProfileId: RoutingProfileUtils.defaultRoutingProfileId,
  );
}
