import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/feature/vpn/domain/net_diagnostics.dart';
import 'package:vpn_plugin/models/net_diagnostic.dart';

void main() {
  test("the engine's line is parsed into the verdict", () {
    final diagnostic = NetDiagnostic.parse(
      'symptom=cut_after_bytes proto=h2 up=8200 down=8100 dur_ms=1000 idle_ms=500 repeat=2 cut=16342',
    );

    expect(diagnostic, isNotNull);
    expect(diagnostic!.symptom, NetDiagnostic.cutAfterBytes);
    expect(diagnostic.protocol, 'h2');
    expect(diagnostic.bytesUp, 8200);
    expect(diagnostic.bytesDown, 8100);
    expect(diagnostic.durationMs, 1000);
    expect(diagnostic.idleMs, 500);
    expect(diagnostic.repeat, 2);
    expect(diagnostic.cutBytes, 16342);
    expect(diagnostic.totalBytes, 16300);
    expect(diagnostic.isCut, isTrue);
    expect(diagnostic.isStall, isFalse);
  });

  test('a session that never came up is a handshake freeze', () {
    final diagnostic = NetDiagnostic.parse('symptom=handshake_freeze proto=h2 up=0 down=0 dur_ms=3000 idle_ms=3000 repeat=1 cut=0');

    expect(diagnostic, isNotNull);
    expect(diagnostic!.isHandshakeFreeze, isTrue);
    expect(diagnostic.isCut, isFalse);
    expect(diagnostic.isStall, isFalse);
  });

  test('a stall is not a cut', () {
    final diagnostic = NetDiagnostic.parse(
      'symptom=stall proto=h3 up=10 down=20 dur_ms=7000 idle_ms=7000 repeat=1 cut=0',
    );

    expect(diagnostic, isNotNull);
    expect(diagnostic!.isStall, isTrue);
    expect(diagnostic.isCut, isFalse);
  });

  test('a line without a symptom is not a verdict', () {
    expect(NetDiagnostic.parse('up=10 down=20'), isNull);
    expect(NetDiagnostic.parse(''), isNull);
    expect(NetDiagnostic.parse(null), isNull);
  });

  test('the last verdict is kept per server, for the window', () {
    final t0 = DateTime(2026, 10, 19, 12);
    final diagnostic = NetDiagnostic.parse(
      'symptom=cut_after_bytes proto=h2 up=8200 down=8100 dur_ms=1000 idle_ms=500 repeat=2 cut=16342',
    )!;

    NetDiagnostics.record('a', diagnostic, at: t0);
    NetDiagnostics.record('b', NetDiagnostic.parse('symptom=stall proto=h2 up=1 down=1')!, at: t0);

    expect(NetDiagnostics.recent('a', within: const Duration(minutes: 1), now: t0), isNotNull);
    expect(NetDiagnostics.recent('a', within: const Duration(minutes: 1), now: t0.add(const Duration(minutes: 2))),
        isNull);
    expect(NetDiagnostics.recent('b', within: const Duration(minutes: 1), now: t0)!.symptom, NetDiagnostic.stall);
    expect(NetDiagnostics.recent('c', within: const Duration(minutes: 1), now: t0), isNull);

    NetDiagnostics.clear('a');
    expect(NetDiagnostics.recent('a', within: const Duration(minutes: 1), now: t0), isNull);
  });
}
