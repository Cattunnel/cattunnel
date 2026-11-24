import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_plugin/domain/cattail_settings.dart';
import 'package:vpn_plugin/domain/configuration_codec.dart';
import 'package:vpn_plugin/domain/deep_link_payload_codec.dart';
import 'package:vpn_plugin/domain/rotation_addresses.dart';
import 'package:vpn_plugin/models/configuration.dart';
import 'package:vpn_plugin/models/endpoint.dart';
import 'package:vpn_plugin/models/ini_document.dart';
import 'package:vpn_plugin/models/socks.dart';
import 'package:vpn_plugin/models/tun.dart';
import 'package:vpn_plugin/models/upstream_protocol.dart';
import 'package:vpn_plugin/models/vpn_mode.dart';

// The bot writes the links (roles/telegram_bot/files/services/trusttunnel.py,
// claude/bot-1595): QUIC varints, a string sequence for 0x53 (varint length +
// UTF-8 per item), varint seconds for 0x54/0x55. The helpers below build the
// same bytes by hand, so the test does not trust our own encoder.
List<int> _varint(int value) {
  if (value <= 0x3f) return [value];
  if (value <= 0x3fff) return [(value >> 8) | 0x40, value & 0xff];
  return [(value >> 24) | 0x80, (value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff];
}

List<int> _tlv(int tag, List<int> value) => [..._varint(tag), ..._varint(value.length), ...value];

List<int> _str(int tag, String value) => _tlv(tag, utf8.encode(value));

List<int> _sequence(int tag, List<String> values) => _tlv(tag, [
  for (final value in values) ...[..._varint(utf8.encode(value).length), ...utf8.encode(value)],
]);

/// The key part every link has: version, host, address, login, password.
List<int> _base() => [
  ..._tlv(0x00, [0x01]),
  ..._str(0x01, 'a1.example.com'),
  ..._str(0x02, '198.51.100.20:443'),
  ..._str(0x05, 'u'),
  ..._str(0x06, 'p'),
];

String _link(List<int> extra) => 'tt://?${base64Url.encode([..._base(), ...extra]).replaceAll('=', '')}';

Endpoint _decode(String link) =>
    const ConfigurationCodec().decode(const DeepLinkPayloadDecoder().convert(link)).endpoint;

final _key = base64Encode(List<int>.generate(32, (i) => i * 7 % 256));

Configuration _config(Endpoint endpoint) => Configuration(
  vpnMode: VpnMode.general,
  endpoint: endpoint,
  tun: const Tun(),
  socks: const Socks(),
);

Endpoint _endpoint({
  bool rotation = false,
  List<String> addresses = const [],
  int min = 0,
  int max = 0,
  bool cattail = false,
  String ports = '',
  String key = '',
  String pattern = '',
  bool xhttp = false,
}) => Endpoint(
  name: 'S',
  hostName: 'vpn.example.com',
  addresses: const ['192.0.2.10:8443'],
  username: 'u',
  password: 'p',
  upStreamProtocol: UpStreamProtocol.http2,
  hasIpv6: false,
  rotationEnabled: rotation,
  rotationAddresses: addresses,
  rotationMinSecs: min,
  rotationMaxSecs: max,
  cattailEnabled: cattail,
  cattailPorts: ports,
  cattailKey: key,
  cattailPattern: pattern,
  xhttpEnabled: xhttp,
);

void main() {
  const codec = ConfigurationCodec();

  group('0x53-0x55 rotation (9a)', () {
    test('a bot-shaped link: each address with its own SNI pool and the term range', () {
      final endpoint = _decode(
        _link([
          ..._sequence(0x53, [
            'a1.example.com:443 a1.example.com a2.example.com',
            'b1.example.com:443 b1.example.com b2.example.com',
          ]),
          ..._tlv(0x54, _varint(600)),
          ..._tlv(0x55, _varint(900)),
        ]),
      );

      expect(endpoint.rotationEnabled, isTrue);
      expect(endpoint.rotationAddresses, [
        'a1.example.com:443 a1.example.com a2.example.com',
        'b1.example.com:443 b1.example.com b2.example.com',
      ]);
      expect(endpoint.rotationMinSecs, 600);
      expect(endpoint.rotationMaxSecs, 900);
    });

    test('the engine config gets one [[endpoint.rotation]] per address and the range in [endpoint]', () {
      final toml = codec.encode(
        _config(
          _endpoint(
            rotation: true,
            addresses: const ['203.0.113.7 a.example.org B.example.org', '[2001:db8::1]:9443'],
            min: 600,
            max: 900,
          ),
        ),
      );

      expect(
        toml,
        contains(
          '[[endpoint.rotation]]\naddress = "203.0.113.7:8443"\nsni_pool = ["a.example.org", "b.example.org"]\n',
        ),
      );
      expect(toml, contains('[[endpoint.rotation]]\naddress = "[2001:db8::1]:9443"\n'));
      expect(toml, contains('rotation_min_secs = 600'));
      expect(toml, contains('rotation_max_secs = 900'));
      // The tables come right after [endpoint], before the next section.
      expect(toml.indexOf('[[endpoint.rotation]]'), lessThan(toml.indexOf('[listener]')));
      expect(toml.indexOf('[endpoint]'), lessThan(toml.indexOf('[[endpoint.rotation]]')));
    });

    test('the config text reads back to the same entries (config file import)', () {
      final endpoint =
          codec
              .decode(
                codec.encode(_config(_endpoint(rotation: true, addresses: const ['203.0.113.7:443 a.example.org']))),
              )
              .endpoint;
      expect(endpoint.rotationAddresses, ['203.0.113.7:443 a.example.org']);
      expect(endpoint.rotationEnabled, isTrue);
    });

    test('a link round trip through our encoder keeps entries, names and range', () {
      final source = _endpoint(
        rotation: true,
        addresses: const ['192.0.2.10', 'backup.example.org:443 x.example.org'],
        min: 120,
        max: 240,
      );
      final decoded = _decode('tt://?${const DeepLinkPayloadEncoder().convert(source)}');
      expect(decoded.rotationAddresses, ['192.0.2.10:8443', 'backup.example.org:443 x.example.org']);
      expect([decoded.rotationMinSecs, decoded.rotationMaxSecs], [120, 240]);
    });

    test('rotation switched off locally: the list stays, the engine and the link get nothing', () {
      final config = _config(_endpoint(addresses: const ['192.0.2.11'], min: 600, max: 900));
      final toml = codec.encode(config);
      expect(toml, isNot(contains('[[endpoint.rotation]]')));
      expect(toml, isNot(contains('rotation_min_secs')));
      expect(config.endpoint.rotationAddresses, ['192.0.2.11']);
      expect(_decode('tt://?${const DeepLinkPayloadEncoder().convert(config.endpoint)}').rotationAddresses, isEmpty);
    });

    test('a wrong entry (bad port, bad name) is skipped, at most 16 reach the engine', () {
      final entries = [
        '192.0.2.11:0',
        '192.0.2.12 not_a_name',
        ...List.generate(18, (index) => '192.0.2.${index + 20}'),
      ];
      final decoded = codec.decode(codec.encode(_config(_endpoint(rotation: true, addresses: entries)))).endpoint;
      expect(decoded.rotationAddresses.length, 16);
      expect(decoded.rotationAddresses.first, '192.0.2.20:8443');
    });

    test('a reversed range is put in order, out-of-range terms are clamped', () {
      final toml = codec.encode(
        _config(_endpoint(rotation: true, addresses: const ['192.0.2.11'], min: 900, max: 100000)),
      );
      expect(toml, contains('rotation_min_secs = 900'));
      expect(toml, contains('rotation_max_secs = 86400'));
      expect(RotationAddresses.parseEntry('192.0.2.1 a.example.org a.example.org', 443)!.sniPool, ['a.example.org']);
    });
  });

  group('0x56-0x59 CatTail', () {
    test('a link with CatTail: on, port range, the 32-byte key and the padding scheme', () {
      final endpoint = _decode(
        _link([
          ..._tlv(0x56, [0x01]),
          ..._str(0x57, '20000-40000'),
          ..._tlv(0x58, base64Decode(_key)),
          ..._str(0x59, 'stop=3\n0=400-1400\n1=100-400\n2=400-500,c,500-1000'),
        ]),
      );
      expect(endpoint.cattailEnabled, isTrue);
      expect(endpoint.cattailPorts, '20000-40000');
      expect(endpoint.cattailKey, _key);
      expect(endpoint.cattailPattern, 'stop=3\n0=400-1400\n1=100-400\n2=400-500,c,500-1000');
    });

    test('the engine config gets [endpoint.cattail] with enabled, ports, key, pattern', () {
      final toml = codec.encode(
        _config(_endpoint(cattail: true, ports: '20000-40000, 443', key: _key, pattern: 'stop=1\n0=400-1400')),
      );
      expect(toml, contains('[endpoint.cattail]\nenabled = true\nports = "20000-40000,443"\nkey = "$_key"\n'));
      expect(toml, contains('pattern = """stop=1\n0=400-1400"""'));
      expect(toml.indexOf('[endpoint.cattail]'), lessThan(toml.indexOf('[listener]')));

      final back = codec.decode(toml).endpoint;
      expect(
        [back.cattailEnabled, back.cattailPorts, back.cattailKey, back.cattailPattern],
        [
          true,
          '20000-40000,443',
          _key,
          'stop=1\n0=400-1400',
        ],
      );
    });

    test('switched off, without a key or ports, or with NineLives: no [endpoint.cattail]', () {
      for (final endpoint in [
        _endpoint(ports: '20000-40000', key: _key),
        _endpoint(cattail: true, ports: '20000-40000'),
        _endpoint(cattail: true, key: _key),
        _endpoint(cattail: true, ports: '20000-40000', key: _key, xhttp: true),
      ]) {
        expect(codec.encode(_config(endpoint)), isNot(contains('[endpoint.cattail]')), reason: endpoint.toString());
      }
    });

    test('a link round trip through our encoder; the off switch from the link stays off', () {
      final source = _endpoint(cattail: true, ports: '443,8443', key: _key, pattern: 'stop=2\n0=100-200\n1=c');
      final decoded = _decode('tt://?${const DeepLinkPayloadEncoder().convert(source)}');
      expect(
        [decoded.cattailEnabled, decoded.cattailPorts, decoded.cattailKey, decoded.cattailPattern],
        [
          true,
          '443,8443',
          _key,
          'stop=2\n0=100-200\n1=c',
        ],
      );

      final off = _decode(
        _link([
          ..._tlv(0x56, [0x00]),
          ..._str(0x57, '443'),
        ]),
      );
      expect(off.cattailEnabled, isFalse);
      expect(off.cattailPorts, '443');
    });

    test('wrong values from a newer generator are dropped, the link still opens', () {
      final endpoint = _decode(
        _link([
          ..._str(0x57, '70000'),
          ..._tlv(0x58, [1, 2, 3]),
          ..._str(0x59, 'zzz'),
        ]),
      );
      expect([endpoint.cattailPorts, endpoint.cattailKey, endpoint.cattailPattern], ['', '', '']);
      // The key as base64 text is taken too.
      expect(CattailSettings.keyFromTag(utf8.encode(_key)), _key);
      expect(CattailSettings.normalizePorts('40000-20000'), isNull);
    });
  });

  test('IniDocument keeps arrays of tables through parse and write', () {
    const text =
        '[endpoint]\nhostname = "h"\n\n[[endpoint.rotation]]\naddress = "a:1"\n\n[[endpoint.rotation]]\naddress = "b:2"\n';
    final document = IniDocument.parse(text);
    expect(document.arrayTables('endpoint.rotation').map((t) => t.getString('address')), ['a:1', 'b:2']);
    expect(
      document.toString(),
      contains('[[endpoint.rotation]]\naddress = "a:1"\n\n[[endpoint.rotation]]\naddress = "b:2"'),
    );
  });
}
