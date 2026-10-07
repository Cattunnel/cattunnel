import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/feature/vpn/domain/anti_dpi_auto.dart';

void main() {
  test('order: 1, 2, 3; what worked goes first, per server and network', () async {
    SharedPreferences.setMockInitialValues({});
    final auto = AntiDpiAuto(await SharedPreferences.getInstance());

    expect(auto.order(serverId: '7', network: 'wifi'), [1, 2, 3]);

    await auto.remember(serverId: '7', network: 'wifi', mode: 3);
    expect(auto.order(serverId: '7', network: 'wifi'), [3, 1, 2]);
    expect(auto.order(serverId: '7', network: 'mobile'), [1, 2, 3]);
    expect(auto.order(serverId: '8', network: 'wifi'), [1, 2, 3]);
  });

  test('a stored value that is no technique is ignored', () async {
    SharedPreferences.setMockInitialValues({'anti_dpi_auto.7.wifi': 9});
    final auto = AntiDpiAuto(await SharedPreferences.getInstance());

    expect(auto.order(serverId: '7', network: 'wifi'), [1, 2, 3]);
  });
}
