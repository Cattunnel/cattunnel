import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/feature/vpn/domain/anti_dpi_auto.dart';
import 'package:trusttunnel/feature/vpn/domain/network_fingerprint.dart';

void main() {
  test('the key of a network: the same network, the same key', () {
    const home = NetworkFingerprint(
      kind: 'wifi',
      gateway: '192.168.1.1',
      dnsServers: ['192.168.1.1'],
      searchDomains: ['home'],
    );
    const same = NetworkFingerprint(
      kind: 'wifi',
      gateway: '192.168.1.1',
      dnsServers: ['192.168.1.1'],
      searchDomains: ['home'],
    );
    const university = NetworkFingerprint(
      kind: 'wifi',
      gateway: '10.10.0.1',
      dnsServers: ['10.10.0.1'],
      searchDomains: ['uni.example.org'],
    );

    expect(home.key, same.key);
    expect(home.key, isNot(university.key));
    // The key says nothing about the gateway itself.
    expect(home.key, isNot(contains('192.168.1.1')));
  });

  test('without anything to tell the networks apart, the kind is the key', () {
    expect(NetworkFingerprint.empty.key, 'other');
    expect(const NetworkFingerprint(kind: 'wifi', gateway: '', dnsServers: [], searchDomains: []).key, 'wifi');
  });

  test('the name of a network: what the person called it', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    const network = NetworkFingerprint(
      kind: 'wifi',
      gateway: '192.168.1.1',
      dnsServers: ['192.168.1.1'],
      searchDomains: [],
    );

    expect(NetworkFingerprint.customName(preferences, network.key), isNull);

    await NetworkFingerprint.rename(preferences, network.key, '  Дома  ');
    expect(NetworkFingerprint.customName(preferences, network.key), 'Дома');

    // Another network has another name.
    expect(NetworkFingerprint.customName(preferences, 'other-key'), isNull);

    await NetworkFingerprint.rename(preferences, network.key, '  ');
    expect(NetworkFingerprint.customName(preferences, network.key), isNull);
  });

  test('the gateway out of /proc/net/route', () {
    const routes = 'Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n'
        'eth0\t00000000\t0101A8C0\t0003\t0\t0\t100\t00000000\t0\t0\t0\n'
        'eth0\t00F0A8C0\t00000000\t0001\t0\t0\t100\t00F0FFFF\t0\t0\t0\n'
        'wlan0\t00000000\t0202A8C0\t0003\t0\t0\t200\t00000000\t0\t0\t0\n';

    // The lowest metric wins, and the address is a little-endian hex.
    expect(NetworkFingerprints.gatewayFromRoutes(routes), '192.168.1.1');
    expect(NetworkFingerprints.gatewayFromRoutes(''), '');
  });

  test('the DNS servers and the search domains out of resolv.conf', () {
    const resolv = '# a comment\n'
        'nameserver 192.168.1.1\n'
        'nameserver 8.8.8.8\n'
        'search home.lan lan\n'
        'options edns0\n';

    final parsed = NetworkFingerprints.dnsFromResolvConf(resolv);

    expect(parsed.dns, ['192.168.1.1', '8.8.8.8']);
    expect(parsed.domains, ['home.lan', 'lan']);
  });
}
