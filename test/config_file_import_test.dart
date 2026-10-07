import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/datasources/local_sources/server_config_import.dart';
import 'package:trusttunnel/data/model/vpn_protocol.dart';

// What the bot's "🐧 Config for Linux / PC" button sends (tt2conf.py,
// build_client_toml): the name only in the first comment, a multi-line PEM.
const _botConfig = '''
# 🇩🇪 Германия 1
# Сгенерировано tt2conf.py. Запуск: sudo trusttunnel_client --config <этот файл>
# Внутри логин и пароль - не пересылайте файл посторонним.

loglevel = "info"
vpn_mode = "general"
killswitch_enabled = false
post_quantum_group_enabled = true
exclusions = ["*.ru", "10.0.0.0/8"]

[endpoint]
hostname = "vpn.example.org"
addresses = ["192.0.2.10:8443"]
custom_sni = ""
has_ipv6 = false
username = "user1"
password = "p@ss \\"word\\""
client_random = "abcd"
skip_verification = false
certificate = """
-----BEGIN CERTIFICATE-----
MIIBszCCAVmgAwIBAgIUQ2F0VHVubmVsVGVzdENlcnQwCgYIKoZIzj0EAwIwEjEQ
-----END CERTIFICATE-----
"""
upstream_protocol = "http2"
anti_dpi = true
dns_upstreams = ["tls://1.1.1.1"]

[listener.tun]
included_routes = ["0.0.0.0/0", "2000::/3"]
excluded_routes = []
mtu_size = 1280
''';

void main() {
  test('the bot config becomes a server', () {
    final server = serverDataFromConfigFile(_botConfig, routingProfileId: '1');

    expect(server.name, '🇩🇪 Германия 1');
    expect(server.domain, 'vpn.example.org');
    expect(server.ipAddress, '192.0.2.10:8443');
    expect(server.username, 'user1');
    expect(server.password, 'p@ss "word"');
    expect(server.tlsPrefix, 'abcd');
    expect(server.antiDpi, isTrue);
    expect(server.ipv6, isFalse);
    expect(server.vpnProtocol, VpnProtocol.http2);
    expect(server.dnsServers, ['tls://1.1.1.1']);
    expect(server.certificate?.data, contains('BEGIN CERTIFICATE'));
    expect(server.routingProfileId, '1');
  });

  test('an explicit name wins over the comment', () {
    final config = _botConfig.replaceFirst('[endpoint]\n', '[endpoint]\nname = "Named"\n');

    expect(serverDataFromConfigFile(config, routingProfileId: '1').name, 'Named');
  });

  test('no comment, no name: the decoder default', () {
    final config = _botConfig.substring(_botConfig.indexOf('loglevel'));

    expect(serverDataFromConfigFile(config, routingProfileId: '1').name, 'Server');
  });

  test('not a config is a FormatException', () {
    expect(() => serverDataFromConfigFile('hello world', routingProfileId: '1'), throwsFormatException);
    expect(() => serverDataFromConfigFile('', routingProfileId: '1'), throwsFormatException);
    final noPassword = _botConfig.replaceFirst(RegExp('password = .*\n'), '');
    expect(() => serverDataFromConfigFile(noPassword, routingProfileId: '1'), throwsFormatException);
  });
}
