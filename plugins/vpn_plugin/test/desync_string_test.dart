import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_plugin/domain/desync_string.dart';

void main() {
  test('accepts what the engine accepts', () {
    for (final text in ['', '  ', '-o1+s -d3+h', '-o3 -d7', '-d7', '-s-5', '-o1 -s2 -d7 -s9', ' -d1\t-s3 ']) {
      expect(DesyncString.validate(text), isNull, reason: text);
    }
  });

  test('rejects what the engine rejects', () {
    final cases = {
      '-r1+s': DesyncStringErrorReason.recordSplit,
      '-o3': DesyncStringErrorReason.oobWithoutTtl,
      '-o3 -s7': DesyncStringErrorReason.oobWithoutTtl,
      '-d2 -o5': DesyncStringErrorReason.oobWithoutTtl,
      '-d': DesyncStringErrorReason.position,
      '-d3+e': DesyncStringErrorReason.position,
      '-d1501': DesyncStringErrorReason.position,
      '-x3': DesyncStringErrorReason.unknown,
      'd3': DesyncStringErrorReason.unknown,
      '-d3 -d4 -d5 -d6 -d7 -d8 -d9 -d10 -d11': DesyncStringErrorReason.tooMany,
    };
    cases.forEach((text, reason) => expect(DesyncString.validate(text)?.reason, reason, reason: text));
  });

  test('normalize', () => expect(DesyncString.normalize('  -o1+s \t -d3+s '), '-o1+s -d3+s'));
}
