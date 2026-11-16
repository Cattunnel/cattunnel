import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/utils/qr_import.dart';

void main() {
  test('a tt:// server link is normalized for the deep link decoder', () {
    final parsed = QrImport.tryParse('  tt://?abc  ');

    expect(parsed, isA<QrImportServerLink>());
    expect((parsed! as QrImportServerLink).link, 'tt://?abc');
  });

  test('a subscription share link keeps its URL, key and name', () {
    final parsed = QrImport.tryParse(
      'cattunnel://subscription?url=https%3A%2F%2Fexample.org%2Fsub&name=Cat',
    );

    expect(parsed, isA<QrImportSubscriptionLink>());
    final subscription = (parsed! as QrImportSubscriptionLink).subscription;
    expect(subscription.url, 'https://example.org/sub');
    expect(subscription.name, 'Cat');
  });

  test('a one-time code link carries the code and the https base', () {
    final parsed = QrImport.tryParse(
      'cattunnel://subscription?code=secret-code&base=https%3A%2F%2Fexample.org',
    );

    expect(parsed, isA<QrImportSubscriptionCode>());
    final code = parsed! as QrImportSubscriptionCode;
    expect(code.code, 'secret-code');
    expect(code.base, 'https://example.org');
  });

  test('the bot page https://host/api/go/<code> becomes the same code and base', () {
    final parsed = QrImport.tryParse('https://example.org/api/go/secret-code');

    expect(parsed, isA<QrImportSubscriptionCode>());
    final code = parsed! as QrImportSubscriptionCode;
    expect(code.code, 'secret-code');
    expect(code.base, 'https://example.org');
  });

  test('the bot page keeps a non-default port in the base', () {
    final parsed = QrImport.tryParse('https://example.org:8443/api/go/secret-code');

    expect(parsed, isA<QrImportSubscriptionCode>());
    expect((parsed! as QrImportSubscriptionCode).base, 'https://example.org:8443');
  });

  test('garbage and http pages are not imported', () {
    expect(QrImport.tryParse(''), isNull);
    expect(QrImport.tryParse('just text'), isNull);
    expect(QrImport.tryParse('https://example.org/other/secret-code'), isNull);
    expect(QrImport.tryParse('http://example.org/api/go/secret-code'), isNull);
    expect(QrImport.tryParse('https://example.org/api/go/'), isNull);
  });
}
