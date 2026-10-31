import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/feature/vpn/domain/connection_diagnostics.dart';

void main() {
  final notBefore = DateTime.utc(2026, 10, 2);
  final notAfter = DateTime.utc(2026, 12, 30);

  test('a clock inside the certificate window is fine', () {
    expect(
      ConnectionDiagnostics.clockOutside(notBefore: notBefore, notAfter: notAfter, now: DateTime.utc(2026, 10, 31)),
      isFalse,
    );
  });

  test('a clock behind the certificate start is wrong', () {
    expect(
      ConnectionDiagnostics.clockOutside(notBefore: notBefore, notAfter: notAfter, now: DateTime.utc(2025, 6, 15)),
      isTrue,
    );
  });

  test('a clock past the certificate end is wrong', () {
    expect(
      ConnectionDiagnostics.clockOutside(notBefore: notBefore, notAfter: notAfter, now: DateTime.utc(2027, 3, 15)),
      isTrue,
    );
  });
}
