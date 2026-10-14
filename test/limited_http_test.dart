import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:trusttunnel/common/utils/limited_http.dart';

http.StreamedResponse _response(List<List<int>> chunks, {int? contentLength}) =>
    http.StreamedResponse(Stream.fromIterable(chunks), 200, contentLength: contentLength);

void main() {
  test('a body within the cap is read whole', () async {
    final body = await readLimited(_response([List.filled(10, 1), List.filled(5, 2)]), 15);
    expect(body.length, 15);
  });

  test('a body past the cap stops with ResponseTooLargeException', () async {
    final endless = http.StreamedResponse(Stream.periodic(Duration.zero, (_) => List.filled(1024, 0)), 200);
    await expectLater(readLimited(endless, 4096), throwsA(isA<ResponseTooLargeException>()));
  });

  test('a declared Content-Length past the cap is refused before reading', () async {
    await expectLater(
      readLimited(_response([<int>[]], contentLength: 1 << 30), 4096),
      throwsA(isA<ResponseTooLargeException>()),
    );
  });
}
