import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/feature/vpn/domain/anti_dpi_auto.dart';
import 'package:trusttunnel/feature/vpn/domain/network_fingerprint.dart';
import 'package:trusttunnel/feature/vpn/domain/networks_memory.dart';

void main() {
  const network = NetworkFingerprint(
    kind: 'wifi',
    gateway: '10.10.0.1',
    dnsServers: ['10.10.0.1'],
    searchDomains: ['uni'],
  );

  test('the networks the app knows about', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final auto = AntiDpiAuto(preferences);

    await NetworkFingerprint.rememberKind(preferences, network);
    await auto.rememberDirectFailure(serverId: 'server-1', network: network.key);
    await auto.remember(serverId: 'server-1', network: network.key, mode: 3);

    final networks = NetworksMemory.all(preferences);

    expect(networks.length, 1);
    expect(networks.first.kind, 'wifi');
    expect(networks.first.needsDpi, isTrue);
    expect(networks.first.modes, [3]);
    expect(networks.first.directFailsUntil, isNotNull);
    // The name of the network is what the person called it.
    expect(networks.first.name, isNull);
    await NetworkFingerprint.rename(preferences, network.key, 'Универ');
    expect(NetworksMemory.all(preferences).first.name, 'Универ');
  });

  test('a network the app knows nothing about is not on the list', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await NetworkFingerprint.rememberKind(preferences, network);

    expect(NetworksMemory.all(preferences), isEmpty);
  });

  test('the memory of a network has a week of life', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final auto = AntiDpiAuto(preferences);
    final now = DateTime(2026, 10, 21, 12);

    await auto.rememberDirectFailure(serverId: 'server-1', network: network.key, now: now);
    final until = NetworksMemory.all(preferences, now: now).first.directFailsUntil;

    expect(until, isNotNull);
    expect(until!.isAfter(now), isTrue);
    // A week later the fact is gone.
    expect(NetworksMemory.all(preferences, now: now.add(const Duration(days: 8))), isEmpty);
  });

  test('forgetting a network and forgetting all of them', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final auto = AntiDpiAuto(preferences);
    const other = NetworkFingerprint(kind: 'mobile', gateway: '', dnsServers: [], searchDomains: []);

    await auto.rememberDirectFailure(serverId: 'server-1', network: network.key);
    await auto.remember(serverId: 'server-1', network: network.key, mode: 1);
    await auto.rememberDirectFailure(serverId: 'server-2', network: other.key);
    await NetworkFingerprint.rename(preferences, network.key, 'Дома');

    expect(NetworksMemory.all(preferences).length, 2);

    await NetworksMemory.forget(preferences, network.key);
    final left = NetworksMemory.all(preferences);
    expect(left.length, 1);
    expect(left.first.key, other.key);

    await NetworksMemory.forgetAll(preferences);
    expect(NetworksMemory.all(preferences), isEmpty);
    // The name of the forgotten network is gone too.
    expect(NetworkFingerprint.customName(preferences, network.key), isNull);
  });

  test('the details: each key, its technique and when it last worked (owner 02.11)', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final auto = AntiDpiAuto(preferences);
    final at = DateTime(2026, 11, 2, 14, 30);

    await NetworkFingerprint.rememberKind(preferences, network);
    await auto.remember(serverId: 'server.de.1', network: network.key, mode: 2, now: at);
    await auto.remember(serverId: 'nl', network: network.key, mode: 1, now: at);

    final details = NetworksMemory.all(preferences).single;
    expect(details.modeByServer, {'server.de.1': 2, 'nl': 1});
    expect(details.seenByServer['server.de.1'], at);
    expect(details.modes, [1, 2]);
  });

  test('a key with the bypass from its subscription marks no network', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final auto = AntiDpiAuto(preferences);

    await NetworkFingerprint.rememberKind(preferences, network);
    await auto.remember(serverId: 'de', network: network.key, mode: 1, bySubscription: true);
    expect(NetworksMemory.all(preferences), isEmpty);
    // The hint still goes first next time.
    expect(auto.order(serverId: 'de', network: network.key, bySubscription: true).first, 1);

    // An old mark of such a key (older versions wrote it) is hidden at once.
    await auto.remember(serverId: 'de', network: network.key, mode: 3);
    expect(NetworksMemory.all(preferences), isNotEmpty);
    expect(NetworksMemory.all(preferences, bySubscription: {'de'}), isEmpty);

    // Forgetting the network takes the key's hint too.
    await NetworksMemory.forgetAll(preferences);
    expect(preferences.getKeys().where((k) => k.startsWith(AntiDpiAuto.subHintKeyPrefix)), isEmpty);
  });
}
