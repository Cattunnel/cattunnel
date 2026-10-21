import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/feature/vpn/domain/anti_dpi_auto.dart';

void main() {
  test('order: two techniques at a time, what worked goes first', () async {
    SharedPreferences.setMockInitialValues({});
    final auto = AntiDpiAuto(await SharedPreferences.getInstance());

    // Not three: three handshakes to the same name are what a filter's
    // freeze keys on.
    expect(auto.order(serverId: '7', network: 'wifi'), [1, 2]);

    await auto.remember(serverId: '7', network: 'wifi', mode: 3);
    expect(auto.order(serverId: '7', network: 'wifi'), [3, 1]);
    expect(auto.order(serverId: '7', network: 'mobile'), [1, 2]);
    expect(auto.order(serverId: '8', network: 'wifi'), [1, 2]);
  });

  test('a stored value that is no technique is ignored', () async {
    SharedPreferences.setMockInitialValues({'anti_dpi_auto.7.wifi': 9});
    final auto = AntiDpiAuto(await SharedPreferences.getInstance());

    expect(auto.order(serverId: '7', network: 'wifi'), [1, 2]);
  });

  test('a failed round moves on: the next attempt tries other techniques', () async {
    SharedPreferences.setMockInitialValues({});
    final auto = AntiDpiAuto(await SharedPreferences.getInstance());

    expect(auto.order(serverId: '7', network: 'wifi'), [1, 2]);

    await auto.advance(serverId: '7', network: 'wifi', count: 2);
    expect(auto.order(serverId: '7', network: 'wifi'), [3, 1]);

    await auto.advance(serverId: '7', network: 'wifi', count: 2);
    expect(auto.order(serverId: '7', network: 'wifi'), [2, 3]);
  });

  test('the network remembers that the plain connection does not work there', () async {
    SharedPreferences.setMockInitialValues({});
    final auto = AntiDpiAuto(await SharedPreferences.getInstance());
    final now = DateTime(2026, 10, 21, 12);

    expect(auto.directFails(serverId: '7', network: 'net1', now: now), isFalse);

    await auto.rememberDirectFailure(serverId: '7', network: 'net1');
    expect(auto.directFails(serverId: '7', network: 'net1', now: now), isTrue);
    // Another network is another network.
    expect(auto.directFails(serverId: '7', network: 'net2', now: now), isFalse);
    expect(auto.directFails(serverId: '8', network: 'net1', now: now), isFalse);

    // The memory has a week of life.
    expect(
      auto.directFails(serverId: '7', network: 'net1', now: now.add(const Duration(days: 6))),
      isTrue,
    );
    expect(
      auto.directFails(serverId: '7', network: 'net1', now: now.add(const Duration(days: 8))),
      isFalse,
    );

    // A plain connection that worked takes the memory away.
    await auto.forgetDirectFailure(serverId: '7', network: 'net1');
    expect(auto.directFails(serverId: '7', network: 'net1', now: now), isFalse);
  });
}
