import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_plugin/domain/configuration_codec.dart';
import 'package:vpn_plugin/models/configuration.dart';
import 'package:vpn_plugin/models/endpoint.dart';
import 'package:vpn_plugin/models/socks.dart';
import 'package:vpn_plugin/models/tun.dart';
import 'package:vpn_plugin/models/upstream_protocol.dart';
import 'package:vpn_plugin/models/vpn_mode.dart';

void main() {
  test('strings from a server are escaped: no TOML smuggled into the engine config', () {
    const evil = 'p"w\\d\nloglevel = "trace"\n[listener.socks]';
    const configuration = Configuration(
      vpnMode: VpnMode.general,
      endpoint: Endpoint(
        name: 'Server',
        hostName: 'www.example.org',
        addresses: ['198.51.100.7:443'],
        username: 'u"ser',
        password: evil,
        upStreamProtocol: UpStreamProtocol.http2,
        hasIpv6: true,
      ),
      tun: Tun(),
      socks: Socks(),
    );
    final toml = const ConfigurationCodec().encode(configuration);
    expect(toml, isNot(contains('\n[listener.socks]')));
    expect(RegExp(r'^loglevel', multiLine: true).allMatches(toml).length, 1);

    final decoded = const ConfigurationCodec().decode(toml).endpoint;
    expect(decoded.password, evil);
    expect(decoded.username, 'u"ser');
  });
}
