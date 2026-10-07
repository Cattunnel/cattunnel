import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/feature/updates/domain/update_service.dart';

// A throwaway key, not the release one: the vector was made with
// tools/sign_latest_json.sh's openssl commands, so this checks that what
// the tool writes is what the app accepts.
const _publicKey = '4WojCYokHE9ZGpHxc0MLljt8fEQys4973WUQJM8cxPM=';
const _signature = 'SPNNhmZxybi1eFDFLyeJlR5OtDymzssmmbgNMJVpWRXIQxtxooHgXwpIGSUjIPNRD1ZyhWGiMqswVeq7nWhnAQ==';
const _body = '{"version":"9.9.9","build":1}';

void main() {
  final key = base64.decode(_publicKey);

  test('accepts the openssl signature of the exact bytes', () async {
    expect(await UpdateService.signatureValid(utf8.encode(_body), _signature, key), isTrue);
    expect(await UpdateService.signatureValid(utf8.encode(_body), '$_signature\n', key), isTrue);
  });

  test('rejects a changed body', () async {
    expect(await UpdateService.signatureValid(utf8.encode(_body.replaceAll('1}', '2}')), _signature, key), isFalse);
    expect(await UpdateService.signatureValid(utf8.encode('$_body '), _signature, key), isFalse);
  });

  test('rejects another key and garbage', () async {
    expect(await UpdateService.signatureValid(utf8.encode(_body), _signature, List.filled(32, 7)), isFalse);
    expect(await UpdateService.signatureValid(utf8.encode(_body), 'not base64!', key), isFalse);
    expect(await UpdateService.signatureValid(utf8.encode(_body), base64.encode([1, 2, 3]), key), isFalse);
  });
}
