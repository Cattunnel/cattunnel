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
}
