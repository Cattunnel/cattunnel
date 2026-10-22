import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    const routes =
        'Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n'
        'eth0\t00000000\t0101A8C0\t0003\t0\t0\t100\t00000000\t0\t0\t0\n'
        'eth0\t00F0A8C0\t00000000\t0001\t0\t0\t100\t00F0FFFF\t0\t0\t0\n'
        'wlan0\t00000000\t0202A8C0\t0003\t0\t0\t200\t00000000\t0\t0\t0\n';

    // The lowest metric wins, and the address is a little-endian hex.
    expect(NetworkFingerprints.gatewayFromRoutes(routes), '192.168.1.1');
    expect(NetworkFingerprints.gatewayFromRoutes(''), '');
  });

  test('the DNS servers and the search domains out of resolv.conf', () {
    const resolv =
        '# a comment\n'
        'nameserver 192.168.1.1\n'
        'nameserver 8.8.8.8\n'
        'search home.lan lan\n'
        'options edns0\n';

    final parsed = NetworkFingerprints.dnsFromResolvConf(resolv);

    expect(parsed.dns, ['192.168.1.1', '8.8.8.8']);
    expect(parsed.domains, ['home.lan', 'lan']);
  });

  test('a mobile network is known by its operator, not by the gateway', () {
    const mts = NetworkFingerprint(
      kind: 'mobile',
      gateway: '10.1.1.1',
      dnsServers: ['1.1.1.1'],
      searchDomains: [],
      operatorCode: '25001',
      operatorName: 'МТС',
    );
    const mtsAnotherCity = NetworkFingerprint(
      kind: 'mobile',
      gateway: '10.9.9.9',
      dnsServers: ['8.8.8.8'],
      searchDomains: [],
      operatorCode: '25001',
      operatorName: 'МТС',
    );
    const megafon = NetworkFingerprint(
      kind: 'mobile',
      gateway: '10.1.1.1',
      dnsServers: ['1.1.1.1'],
      searchDomains: [],
      operatorCode: '25002',
      operatorName: 'МегаФон',
    );

    expect(mts.key, 'mobile:25001');
    expect(mtsAnotherCity.key, mts.key);
    expect(megafon.key, isNot(mts.key));
  });

  test('a mobile network without an operator code stays one network', () {
    const unknown = NetworkFingerprint(kind: 'mobile', gateway: '', dnsServers: [], searchDomains: []);

    expect(unknown.key, 'mobile');
  });

  test('the operator name is the default name of a mobile network', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    const network = NetworkFingerprint(
      kind: 'mobile',
      gateway: '10.1.1.1',
      dnsServers: [],
      searchDomains: [],
      operatorCode: '25001',
      operatorName: 'МТС',
    );

    await NetworkFingerprint.rememberKind(preferences, network);
    expect(NetworkFingerprint.operatorNameOf(preferences, network.key), 'МТС');
  });

  test('Wi-Fi at the same time as mobile data: the Wi-Fi key, no operator', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('cattunnel/apps');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => {
        'kind': 'wifi',
        'gateway': '192.168.1.1',
        'dns': ['192.168.1.1'],
        'domains': ['home.arpa'],
        // Even if the platform sends the SIM operator, it says nothing
        // about Wi-Fi and must not enter the key.
        'operatorCode': '25001',
        'operatorName': 'МТС',
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );

    final fingerprint = await NetworkFingerprints.current(kind: 'mobile');

    expect(fingerprint.kind, 'wifi');
    expect(fingerprint.key, isNot(contains('mobile')));
    expect(fingerprint.key, isNot(contains('25001')));
  });

  test('only mobile data: the key is the operator of the data SIM', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('cattunnel/apps');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => {
        'kind': 'mobile',
        'gateway': '10.1.1.1',
        'dns': ['1.1.1.1'],
        'domains': <String>[],
        'operatorCode': '25001',
        'operatorName': 'МТС',
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );

    final fingerprint = await NetworkFingerprints.current(kind: 'wifi');

    expect(fingerprint.kind, 'mobile');
    expect(fingerprint.key, 'mobile:25001');
  });
}
