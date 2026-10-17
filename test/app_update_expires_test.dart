import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/feature/updates/domain/app_update.dart';

void main() {
  Map<String, Object?> manifest([Object? expires]) => {
    'version': '1.5.6',
    'build': 6056,
    'notes': '',
    'apks': {
      'universal': {'url': 'https://example.org/a.apk', 'sha256': 'ab' * 32},
    },
    'expires': ?expires,
  };

  test('expires is read when present and optional for older manifests', () {
    expect(AppUpdate.fromJson(manifest()).expires, isNull);
    expect(AppUpdate.fromJson(manifest('2027-01-15T00:00:00Z')).expires, DateTime.utc(2027, 1, 15));
    expect(() => AppUpdate.fromJson(manifest('not a date')), throwsFormatException);
  });
}
