import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_plugin/domain/configuration_codec.dart';
import 'package:vpn_plugin/domain/deep_link_payload_codec.dart';
import 'package:vpn_plugin/models/configuration.dart';
import 'package:vpn_plugin/models/endpoint.dart';
import 'package:vpn_plugin/models/socks.dart';
import 'package:vpn_plugin/models/tun.dart';
import 'package:vpn_plugin/models/upstream_protocol.dart';
import 'package:vpn_plugin/models/vpn_mode.dart';

Configuration _config(List<String> pool) => Configuration(
  vpnMode: VpnMode.general,
  endpoint: Endpoint(
    name: 'S',
    hostName: 'vpn.example.com',
    addresses: const ['203.0.113.5:443'],
    username: 'u',
    password: 'p',
    upStreamProtocol: UpStreamProtocol.http2,
    hasIpv6: true,
    sniPool: pool,
  ),
  tun: const Tun(),
  socks: const Socks(),
);

void main() {
  const codec = ConfigurationCodec();

  test('the SNI pool is written as sni_pool and read back', () {
    final text = codec.encode(_config(const ['a.example.org', 'b.example.org']));

    expect(text, contains('sni_pool'));
    expect(codec.decode(text).endpoint.sniPool, const ['a.example.org', 'b.example.org']);
  });

  test('an empty pool writes no sni_pool', () {
    final text = codec.encode(_config(const []));

    expect(text, isNot(contains('sni_pool')));
    expect(codec.decode(text).endpoint.sniPool, isEmpty);
  });

  test('the pool is cut to the engine limit of 8 and empty names are dropped', () {
    final pool = List.generate(10, (i) => 'n$i.example.org');

    expect(codec.decode(codec.encode(_config(['', ...pool]))).endpoint.sniPool, pool.take(8).toList());
  });

  test('a tt:// link carries the pool through the deep-link codec', () {
    final endpoint = _config(const ['a.example.org', 'b.example.org']).endpoint;
    final link = 'tt://?${const DeepLinkPayloadEncoder().convert(endpoint)}';
    final decoded = codec.decode(const DeepLinkPayloadDecoder().convert(link)).endpoint;

    expect(decoded.sniPool, const ['a.example.org', 'b.example.org']);
  });

  test('a link without tag 0x52 gives an empty pool', () {
    final endpoint = _config(const []).endpoint;
    final link = 'tt://?${const DeepLinkPayloadEncoder().convert(endpoint)}';

    expect(codec.decode(const DeepLinkPayloadDecoder().convert(link)).endpoint.sniPool, isEmpty);
  });
}
