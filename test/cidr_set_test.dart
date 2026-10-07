import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/ru_lists/cidr_set.dart';

void main() {
  test('merges overlapping and adjacent v4 networks', () {
    expect(CidrSet.v4(['10.0.0.0/25', '10.0.0.128/25', '10.0.0.64/26', 'junk', '# c', '10.0.1.5']).toCidrs(),
        ['10.0.0.0/24', '10.0.1.5/32']);
  });

  test('subtracts', () {
    expect(CidrSet.v4(['10.0.0.0/24']).subtract(CidrSet.v4(['10.0.0.128/25'])).toCidrs(), ['10.0.0.0/25']);
    expect(CidrSet.v4(['10.0.0.0/24']).subtract(CidrSet.v4(['10.0.0.1/32'])).toCidrs(),
        ['10.0.0.0/32', '10.0.0.2/31', '10.0.0.4/30', '10.0.0.8/29', '10.0.0.16/28', '10.0.0.32/27', '10.0.0.64/26', '10.0.0.128/25']);
    expect(CidrSet.v4(['10.0.0.0/24']).subtract(CidrSet.v4(['10.0.0.0/16'])).toCidrs(), isEmpty);
  });

  test('v6: parse, merge, skip v4', () {
    expect(CidrSet.v6(['2a00::/16', '2a00:1::/32', '2a01::/16', '1.2.3.0/24', '::1']).toCidrs(),
        ['0:0:0:0:0:0:0:1/128', '2a00:0:0:0:0:0:0:0/15']);
  });

  test('prefix length', () {
    expect(cidrPrefixLength('1.2.3.0/24'), 24);
    expect(cidrPrefixLength('1.2.3.4'), isNull);
  });
}
