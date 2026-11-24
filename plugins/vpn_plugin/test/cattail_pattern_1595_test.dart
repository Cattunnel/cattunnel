import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_plugin/domain/cattail_settings.dart';

// The padding scheme of CatTail as the endpoint reads it: docs/cattail.md
// section 4.1 of the server (claude/server-1595) and PaddingScheme::parse in
// lib/src/cattail.rs. The app, the bot and the menu must agree with it on every line.
void main() {
  String? check(String raw) => CattailSettings.normalizePattern(raw);

  const endpointDefault = 'stop=3\n0=400-1400,c,200-900\n1=300-1200,c,100-700\n2=100-600,c\nmid=0-32\nend=0-96';

  test('the default scheme of the endpoint is accepted as it is', () {
    expect(check(endpointDefault), endpointDefault);
  });

  test('an empty scheme stays empty: the engine default', () {
    expect(check(''), '');
    expect(check('  \n ; \r\n'), '');
  });

  test('stop is one number from 0 to 16', () {
    expect(check('stop=0'), 'stop=0');
    expect(check('stop=16'), 'stop=16');
    expect(check('stop=17'), isNull);
    expect(check('stop=1-2'), isNull);
    expect(check('stop=x'), isNull);
  });

  test('an item is lo-hi or a single size from 48 to 16448, or c', () {
    expect(check('stop=1\n0=48-16448'), 'stop=1\n0=48-16448');
    expect(check('stop=1\n0=600'), 'stop=1\n0=600');
    expect(check('stop=1\n0=47-100'), isNull);
    expect(check('stop=1\n0=30-30'), isNull);
    expect(check('stop=1\n0=100-16449'), isNull);
    expect(check('stop=1\n0=500-400'), isNull);
    expect(check('stop=1\n0=c'), 'stop=1\n0=c');
    expect(check('stop=1\n0=400-1400,,c'), isNull);
    expect(check('stop=1\n0='), isNull);
  });

  test('at most 16 items in a line, at most 16 lines (0..15)', () {
    final sixteen = List.filled(16, '100-200').join(',');
    expect(check('stop=1\n0=$sixteen'), 'stop=1\n0=$sixteen');
    expect(check('stop=1\n0=$sixteen,c'), isNull);
    expect(check('stop=16\n15=c'), 'stop=16\n15=c');
    expect(check('stop=16\n16=c'), isNull);
  });

  test('mid and end are 0..4096, nonce is 0..24', () {
    expect(check('mid=0-4096\nend=5\nnonce=0-24'), 'mid=0-4096\nend=5\nnonce=0-24');
    expect(check('mid=0-4097'), isNull);
    expect(check('end=10-5'), isNull);
    expect(check('nonce=0-25'), isNull);
  });

  test('separators: a new line or a semicolon; spaces are ignored; unknown keys are skipped', () {
    expect(check('stop = 3 ; 0 = 400 - 1400 , c ; future=whatever'), 'stop=3\n0=400-1400,c');
    expect(check('stop=1\r\n0=100-200\r\n'), 'stop=1\n0=100-200');
  });

  test('a line without = makes the whole scheme invalid', () {
    expect(check('stop=1\nnonsense'), isNull);
  });

  test('a scheme that is too long is refused', () {
    expect(check('stop=1\n${List.filled(400, 'future=aaaaaaaaaa').join('\n')}'), isNull);
  });
}
