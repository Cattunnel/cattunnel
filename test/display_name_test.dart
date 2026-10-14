import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/utils/display_name.dart';

void main() {
  test('bidi overrides, isolates and control characters are dropped', () {
    // Built from code points: the analyzer rightly flags them in literals.
    final rlo = String.fromCharCode(0x202E);
    final lri = String.fromCharCode(0x2066);
    final pdi = String.fromCharCode(0x2069);
    expect(sanitizeDisplayName('Германия${rlo}1 gnorw'), 'Германия1 gnorw');
    expect(sanitizeDisplayName('${lri}NL$pdi\u200F'), 'NL');
    expect(sanitizeDisplayName('US\u0000\u0007\n\t'), 'US');
  });

  test('flags and emoji sequences survive', () {
    expect(sanitizeDisplayName('🇩🇪 Германия 1'), '🇩🇪 Германия 1');
    expect(sanitizeDisplayName('🏳️‍🌈 Резерв'), '🏳️‍🌈 Резерв');
  });
}
