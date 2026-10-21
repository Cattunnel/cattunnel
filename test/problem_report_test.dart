import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/feature/support/problem_report.dart';

void main() {
  test('report sanitizer cuts secrets, keeps what an admin needs', () {
    final out = ProblemReport.sanitize(
      'password = "hunter2"\n'
      'username: ivan\n'
      'key AGE-SECRET-KEY-1QQQ9Z8XWV\n'
      'link tt://abcDEF123?x=1\n'
      'sub https://sub.example.org/sub/9f8e7d6c?token=abc\n'
      'Server: Германия - vpn.example.org / 203.0.113.96:443, http2',
    );
    expect(out, isNot(contains('hunter2')));
    expect(out, isNot(contains('ivan')));
    expect(out, isNot(contains('1QQQ9Z8XWV')));
    expect(out, isNot(contains('abcDEF123')));
    expect(out, isNot(contains('9f8e7d6c')));
    expect(out, contains('https://sub.example.org/<path cut>'));
    // The domain of the server stays, the address does not: the report goes
    // to a chat, and the address of the server is not the admin's business.
    expect(out, contains('vpn.example.org'));
    expect(out, isNot(contains('203.0.113.96')));
  });

  test('report sanitizer cuts every address, v4 and v6', () {
    final out = ProblemReport.sanitize(
      'client 198.51.100.7:44300, gateway 2001:db8::1, link 2a00:1450:4009:80f::200e\n',
    );
    expect(out, isNot(contains('198.51.100.7')));
    expect(out, isNot(contains('2001:db8::1')));
    expect(out, isNot(contains('2a00:1450:4009:80f::200e')));
  });

  test('report sanitizer cuts the hardware addresses', () {
    final out = ProblemReport.sanitize('mac aa:bb:cc:dd:ee:ff, wifi 00:11:22:33:44:55\n');

    expect(out, isNot(contains('aa:bb:cc:dd:ee:ff')));
    expect(out, isNot(contains('00:11:22:33:44:55')));
  });
}
