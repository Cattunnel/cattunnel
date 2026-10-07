import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_plugin/domain/configuration_codec.dart';
import 'package:vpn_plugin/models/configuration.dart';
import 'package:vpn_plugin/models/endpoint.dart';
import 'package:vpn_plugin/models/socks.dart';
import 'package:vpn_plugin/models/tun.dart';
import 'package:vpn_plugin/models/upstream_protocol.dart';
import 'package:vpn_plugin/models/vpn_mode.dart';

Configuration _config(Tun tun) => Configuration(
  vpnMode: VpnMode.general,
  endpoint: const Endpoint(
    name: 'S',
    hostName: 'vpn.example.com',
    addresses: ['203.0.113.5:443'],
    username: 'u',
    password: 'p',
    upStreamProtocol: UpStreamProtocol.http2,
    hasIpv6: true,
  ),
  tun: tun,
  socks: const Socks(),
);

void main() {
  const codec = ConfigurationCodec();

  test('app lists round trip under [listener.tun]', () {
    const tun = Tun(excludedApps: ['ru.sberbankmobile', 'com.vkontakte.android'], includedApps: ['org.telegram.messenger']);
    final text = codec.encode(_config(tun));
    expect(text, contains('excluded_apps'));
    expect(text, contains('included_apps'));
    final decoded = codec.decode(text).tun;
    expect(decoded.excludedApps, tun.excludedApps);
    expect(decoded.includedApps, tun.includedApps);
  });

  test('empty lists are not written (desktop CLI, unpatched engine)', () {
    final text = codec.encode(_config(const Tun()));
    expect(text, isNot(contains('excluded_apps')));
    expect(text, isNot(contains('included_apps')));
    expect(codec.decode(text).tun.excludedApps, isEmpty);
  });
}
