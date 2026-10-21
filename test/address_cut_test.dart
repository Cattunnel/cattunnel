import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/utils/address_cut.dart';

void main() {
  test('cuts the addresses', () {
    final out = AddressCut.cut(
      'client 203.0.113.96:443\n'
      'server 2001:db8::1\n'
      'loopback [::1]:443\n'
      'v4 mapped ::ffff:203.0.113.96\n',
    );
    expect(out, isNot(contains('203.0.113.96')));
    expect(out, isNot(contains('2001:db8::1')));
    expect(out, isNot(contains('::1')));
  });

  test('keeps what only looks like an address', () {
    final out = AddressCut.cut(
      '2026-10-21T21:29:00.123+00:00 2026.10.21 version 1.2.3\n'
      'port 443  mask 255.255.255.0\n',
    );
    expect(out, contains('21:29:00'));
    expect(out, contains('2026.10.21'));
    expect(out, contains('1.2.3'));
    expect(out, contains('443'));
    // 255.255.255.0 is an address, the mask goes too.
    expect(out, isNot(contains('255.255.255.0')));
  });

  test('cuts the hardware addresses too', () {
    final out = AddressCut.cut(
      'client aa:bb:cc:dd:ee:ff\n'
      'upper AA:BB:CC:DD:EE:FF\n'
      'dashes aa-bb-cc-dd-ee-ff\n'
      'eui64 00:11:22:33:44:55:66:77\n',
    );
    expect(out, isNot(contains('aa:bb:cc:dd:ee:ff')));
    expect(out, isNot(contains('AA:BB:CC:DD:EE:FF')));
    expect(out, isNot(contains('aa-bb-cc-dd-ee-ff')));
    expect(out, isNot(contains('00:11:22:33:44:55:66:77')));
  });
}
