import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/feature/vpn/domain/connection_diagnostics.dart';

void main() {
  test('Date header of an HTTP response head', () {
    const head =
        'HTTP/1.1 301 Moved Permanently\r\n'
        'Server: nginx\r\n'
        'date: Wed, 07 Oct 2026 19:30:00 GMT\r\n'
        'Location: https://ya.ru/\r\n'
        '\r\n';
    expect(ConnectionDiagnostics.httpDateOf(head), DateTime.utc(2026, 10, 7, 19, 30));
  });

  test('no Date, a bad Date or a Date only in the body - null', () {
    expect(ConnectionDiagnostics.httpDateOf('HTTP/1.1 200 OK\r\nServer: x\r\n\r\n'), isNull);
    expect(ConnectionDiagnostics.httpDateOf('HTTP/1.1 200 OK\r\nDate: yesterday\r\n\r\n'), isNull);
    expect(ConnectionDiagnostics.httpDateOf('HTTP/1.1 200 OK\r\n\r\nDate: Wed, 07 Oct 2026 19:30:00 GMT\r\n'), isNull);
  });

  test('the limit is an hour', () {
    expect(ConnectionDiagnostics.clockSkewLimit, const Duration(hours: 1));
  });
}
