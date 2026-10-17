import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/logging/sanitizer/engine_line_scrubber.dart';

void main() {
  test('credentials, tokens and links are removed, IPs keep the network part', () {
    const line =
        'Using endpoint: name=nl, address=203.0.113.5:443 username="alice" password=s3cr3t '
        'client_random_auth_key = 00112233445566778899aabbccddeeff '
        'GET https://example.org/api/ct/AbC-123_xyz tt://?AAEBDAZT v6 2001:db8:1:2::5';
    final out = EngineLineScrubber.scrub(line);
    for (final secret in ['alice', 's3cr3t', '0011223344', 'AbC-123_xyz', 'AAEBDAZT', '113.5', '1:2::5']) {
      expect(out, isNot(contains(secret)), reason: secret);
    }
    expect(out, contains('203.0.*.*:443'));
    expect(out, contains('2001:db8:*'));
    expect(out, contains('name=nl'));
    expect(out, contains('example.org'));
  });
}
