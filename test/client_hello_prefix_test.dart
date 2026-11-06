import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/datasources/local_sources/server_config_import.dart';
import 'package:vpn_plugin/deep_link_manager.dart';
import 'package:vpn_plugin/domain/deep_link_payload_codec.dart';
import 'package:vpn_plugin/models/endpoint.dart';
import 'package:vpn_plugin/models/upstream_protocol.dart';

void main() {
  for (final prefix in ['abcd', 'invalid-prefix', 'aabb/ffff']) {
    test('0x0B is ignored and 0x0F survives ($prefix)', () async {
      final endpoint = Endpoint(
        name: 'test',
        addresses: const ['192.0.2.1:443'],
        hostName: 'example.org',
        username: 'user',
        password: 'password',
        upStreamProtocol: UpStreamProtocol.http2,
        hasIpv6: true,
        clientRandom: prefix,
        clientRandomAuthKey: '0123456789abcdef0123456789abcdef',
      );
      final payload = const DeepLinkPayloadEncoder().convert(endpoint);
      final config = await DeepLinkManagerImpl().getConfigurationByBase64(base64: 'tt://?$payload');
      expect(config.endpoint.clientRandom, isEmpty);
      expect(config.endpoint.clientRandomAuthKey, '0123456789abcdef0123456789abcdef');
      final server = serverDataFromEndpoint(config.endpoint, routingProfileId: '1');
      expect(server.tlsPrefix, isNull);
      expect(server.tlsAuthKey, endpoint.clientRandomAuthKey);
    });
  }
}
