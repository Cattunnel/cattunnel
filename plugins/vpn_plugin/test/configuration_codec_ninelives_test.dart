import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_plugin/domain/configuration_codec.dart';
import 'package:vpn_plugin/models/configuration.dart';
import 'package:vpn_plugin/models/endpoint.dart';
import 'package:vpn_plugin/models/socks.dart';
import 'package:vpn_plugin/models/tun.dart';
import 'package:vpn_plugin/models/upstream_protocol.dart';
import 'package:vpn_plugin/models/vpn_mode.dart';

Configuration _config({required bool xhttp, required String key}) => Configuration(
  vpnMode: VpnMode.general,
  endpoint: Endpoint(
    name: 'S',
    hostName: 'vpn.example.com',
    addresses: const ['203.0.113.5:443'],
    username: 'u',
    password: 'p',
    upStreamProtocol: UpStreamProtocol.http2,
    hasIpv6: true,
    xhttpEnabled: xhttp,
    xhttpServerKey: key,
  ),
  tun: const Tun(),
  socks: const Socks(),
);

void main() {
  const codec = ConfigurationCodec();

  test('an XHTTP server with a key writes xhttp_server_key', () {
    final text = codec.encode(_config(xhttp: true, key: 'public-key'));

    expect(text, contains('xhttp_server_key'));
    expect(codec.decode(text).endpoint.xhttpServerKey, 'public-key');
  });

  test('an XHTTP server without a key writes no xhttp_server_key', () {
    final text = codec.encode(_config(xhttp: true, key: ''));

    expect(text, isNot(contains('xhttp_server_key')));
    expect(codec.decode(text).endpoint.xhttpServerKey, isEmpty);
  });

  test('a non-XHTTP server does not write the key either', () {
    final text = codec.encode(_config(xhttp: false, key: 'public-key'));

    expect(text, isNot(contains('xhttp_server_key')));
  });
}
