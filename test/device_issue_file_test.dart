import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/utils/device_issue_file.dart';
import 'package:trusttunnel/common/utils/subscription_share_link.dart';

/// Подписанный файл выдачи: тот же формат, что делает бот (тело в base64,
/// подпись Ed25519, открытый ключ рядом).
Future<String> _signedFile({String code = 'code123', bool tamper = false}) async {
  final algorithm = Ed25519();
  final pair = await algorithm.newKeyPair();
  final publicKey = await pair.extractPublicKey();
  final publicBytes = await publicKey.bytes;

  final body = jsonEncode({
    'code': code,
    'base': ['https://www.example.org'],
    'name': 'Германия',
    'issued': 1,
  });
  final payload = utf8.encode(body);
  final signature = await algorithm.sign(payload, keyPair: pair);

  return jsonEncode({
    'code': code,
    'base': ['https://www.example.org'],
    'name': 'Германия',
    'issued': 1,
    'payload': base64.encode(payload),
    'sig': base64.encode(signature.bytes),
    'key': base64.encode(publicBytes),
  });
}

void main() {
  test('a signed file is accepted and gives the code', () async {
    final file = await _signedFile();
    final parsed = await DeviceIssueFile.tryParse(file);

    expect(parsed, isNotNull);
    expect(parsed!.code, 'code123');
    expect(parsed.base, ['https://www.example.org']);
    expect(parsed.name, 'Германия');
  });

  test('a file with a broken signature is refused', () async {
    final file = await _signedFile();
    final data = jsonDecode(file) as Map<String, dynamic>;
    final signature = base64.decode('${data['sig']}');
    signature[0] = signature[0] ^ 0xff;
    data['sig'] = base64.encode(signature);

    expect(await DeviceIssueFile.tryParse(jsonEncode(data)), isNull);
  });

  test('a file with a changed signed body is refused', () async {
    final file = await _signedFile();
    final data = jsonDecode(file) as Map<String, dynamic>;
    final body = jsonDecode(utf8.decode(base64.decode('${data['payload']}'))) as Map<String, dynamic>;
    body['code'] = 'someone-else';
    data['payload'] = base64.encode(utf8.encode(jsonEncode(body)));

    expect(await DeviceIssueFile.tryParse(jsonEncode(data)), isNull);
  });

  test('the fields next to the signature are not trusted', () async {
    final file = await _signedFile();
    final data = jsonDecode(file) as Map<String, dynamic>;
    data['code'] = 'someone-else';

    final parsed = await DeviceIssueFile.tryParse(jsonEncode(data));
    expect(parsed, isNotNull);
    expect(parsed!.code, 'code123');
  });

  test('a file that is not ours at all is refused', () async {
    expect(await DeviceIssueFile.tryParse('{"hello": "world"}'), isNull);
    expect(await DeviceIssueFile.tryParse('not json at all'), isNull);
  });

  test('the one-time link gives the code and the server address', () {
    final parsed = SubscriptionShareLink.tryDecodeCode(
      'cattunnel://subscription?code=abc123&base=https%3A%2F%2Fwww.example.org',
    );

    expect(parsed, isNotNull);
    expect(parsed!.code, 'abc123');
    expect(parsed.base, 'https://www.example.org');
  });

  test('a link without a code or without a server is not ours', () {
    expect(SubscriptionShareLink.tryDecodeCode('cattunnel://subscription?url=x'), isNull);
    expect(SubscriptionShareLink.tryDecodeCode('cattunnel://subscription?code=x'), isNull);
    expect(
      SubscriptionShareLink.tryDecodeCode(
        'cattunnel://subscription?code=x&base=http%3A%2F%2Fevil.example',
      ),
      isNull,
    );
    expect(SubscriptionShareLink.tryDecodeCode('tt://?abc'), isNull);
  });
}
