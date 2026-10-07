import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/feature/vpn/domain/connect_failures.dart';
import 'package:vpn_plugin/models/connect_failure.dart';

void main() {
  test('a ClientHello without an answer freezes the address for the window, per server', () {
    final t0 = DateTime(2026, 10, 3, 12);
    ConnectFailures.record('a', ConnectFailure.helloNoAnswer, at: t0);
    ConnectFailures.record('b', ConnectFailure.helloReset, at: t0);

    expect(ConnectFailures.isFrozen('a', now: t0.add(const Duration(seconds: 119))), isTrue);
    expect(ConnectFailures.isFrozen('a', now: t0.add(ConnectFailures.freezeWindow)), isFalse);
    expect(ConnectFailures.isFrozen('b', now: t0), isFalse);
    expect(ConnectFailures.isFrozen('c', now: t0), isFalse);

    ConnectFailures.clear('a');
    expect(ConnectFailures.isFrozen('a', now: t0), isFalse);
  });

  test('failure names match the engine tags', () {
    expect(ConnectFailure.fromValue('hello_no_answer'), ConnectFailure.helloNoAnswer);
    expect(ConnectFailure.fromValue('hello_reset'), ConnectFailure.helloReset);
    expect(ConnectFailure.fromValue('connect'), ConnectFailure.connect);
    expect(ConnectFailure.fromValue('none'), isNull);
  });
}
