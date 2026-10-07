import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/ru_lists/cidr_set.dart';
import 'package:trusttunnel/feature/server/servers/domain/ru_exit_prompt.dart';

void main() {
  test('Russian server names: whole words and the flag only', () {
    for (final name in ['Россия', 'RU Москва', '🇷🇺 дом', 'Russia-1', 'СПб (дача)', 'vpn-ru']) {
      expect(RuExitPrompt.looksRussianName(name), isTrue, reason: name);
    }
    for (final name in ['Europe', 'Нидерланды (Каскад)', 'Германия', 'Truenas', 'Peru', 'Brussels']) {
      expect(RuExitPrompt.looksRussianName(name), isFalse, reason: name);
    }
  });

  test('address inside the Russian networks', () {
    final v4 = CidrSet.v4(['5.45.200.0/21', '77.88.0.0/18']).toCidrs();
    expect(cidrsContain(v4, '5.45.201.53'), isTrue);
    expect(cidrsContain(v4, '203.0.113.96'), isFalse);
    final v6 = CidrSet.v6(['2a02:6b8::/29']).toCidrs();
    expect(cidrsContain(v6, '2a02:6b8::1'), isTrue);
    expect(cidrsContain(v6, '2001:db8::1'), isFalse);
  });
}
