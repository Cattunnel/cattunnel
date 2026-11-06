import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/utils/direct_request_retry.dart';

void main() {
  test('transient failure gets exactly one fresh attempt', () async {
    var attempts = 0;
    final result = await retryDirectRead(() async {
      if (++attempts == 1) throw const SocketException('offline');
      return 'ok';
    });
    expect(result, 'ok');
    expect(attempts, 2);
  });
  test('second failure propagates; invalid data is never retried', () async {
    var attempts = 0;
    await expectLater(
      retryDirectRead(() async {
        attempts++;
        throw TimeoutException('timeout');
      }),
      throwsA(isA<TimeoutException>()),
    );
    expect(attempts, 2);
    attempts = 0;
    await expectLater(
      retryDirectRead(() async {
        attempts++;
        throw const FormatException('signature');
      }),
      throwsFormatException,
    );
    expect(attempts, 1);
  });
}
