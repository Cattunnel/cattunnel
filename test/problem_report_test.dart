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
    expect(out, contains('203.0.113.96:443'));
  });
}
