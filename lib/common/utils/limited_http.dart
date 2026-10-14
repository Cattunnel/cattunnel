import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A response body bigger than the caller allows.
class ResponseTooLargeException implements IOException {
  final int maxBytes;

  const ResponseTooLargeException(this.maxBytes);

  @override
  String toString() => 'Response body is larger than $maxBytes bytes';
}

/// Reads [response]'s body, at most [maxBytes]: a broken or hostile server
/// can't make the app read an endless body into memory.
Future<Uint8List> readLimited(http.StreamedResponse response, int maxBytes) async {
  final declared = response.contentLength;
  if (declared != null && declared > maxBytes) throw ResponseTooLargeException(maxBytes);
  final body = BytesBuilder(copy: false);
  await for (final chunk in response.stream) {
    if (body.length + chunk.length > maxBytes) throw ResponseTooLargeException(maxBytes);
    body.add(chunk);
  }

  return body.takeBytes();
}

/// GET [url] with the body capped at [maxBytes]; [timeout] covers the whole request.
Future<(int statusCode, Uint8List body)> getLimited(
  Uri url, {
  required int maxBytes,
  required Duration timeout,
}) async {
  final client = http.Client();
  try {
    return await () async {
      final response = await client.send(http.Request('GET', url));

      return (response.statusCode, await readLimited(response, maxBytes));
    }().timeout(timeout);
  } finally {
    client.close();
  }
}
