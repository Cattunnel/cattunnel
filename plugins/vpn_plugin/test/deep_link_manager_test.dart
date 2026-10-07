import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_plugin/deep_link_manager.dart';
import 'package:vpn_plugin/models/endpoint.dart';
import 'package:vpn_plugin/models/upstream_protocol.dart';

void main() {
  // The app imports links and subscriptions through this, on every platform:
  // the engine's native decoder (Android) dropped CatTunnel's tags.
  test('CatTunnel tags survive the import path', () async {
    final manager = DeepLinkManagerImpl();
    final link = manager.buildLink(
      endpoint: const Endpoint(
        name: 'Lab',
        hostName: 'vpn.example.com',
        addresses: ['203.0.113.5:443'],
        username: 'alice',
        password: 's3cr3t',
        upStreamProtocol: UpStreamProtocol.http2,
        hasIpv6: false,
        antiDpi: true,
        antiDpiMode: 5,
        antiDpiDesync: '-o1+s -d3+s',
        tlsProfile: 'firefox',
        h2PaddingFrames: 8,
        ruExit: true,
      ),
    );
    final endpoint = (await manager.getConfigurationByBase64(base64: link)).endpoint;

    expect(endpoint.antiDpi, isTrue);
    expect(endpoint.antiDpiMode, 5);
    expect(endpoint.antiDpiDesync, '-o1+s -d3+s');
    expect(endpoint.tlsProfile, 'firefox');
    expect(endpoint.h2PaddingFrames, 8);
    expect(endpoint.ruExit, isTrue);
  });
}
