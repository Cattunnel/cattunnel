import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/feature/support/desktop_report.dart';

void main() {
  test('desktop saves in Downloads then copies report', () async {
    final events = <String>[];
    final report = DesktopReport(
      downloads: () async => '/downloads',
      home: () => '/home',
      exists: (_) async => true,
      write: (path, text) async {
        events.add('$path:$text');
      },
      copy: (text) async {
        events.add('clipboard:$text');
      },
    );
    final path = await report.save('report', now: DateTime(2026, 11));
    expect(path, startsWith('/downloads/cattunnel-report-'));
    expect(path, endsWith('.txt'));
    expect(events, ['$path:report', 'clipboard:report']);
  });

  for (final unavailable in [false, true]) {
    test('desktop falls back home when Downloads ${unavailable ? 'throws' : 'is missing'}', () async {
      final report = DesktopReport(
        downloads: () async {
          if (unavailable) throw StateError('provider');
          return '/missing';
        },
        home: () => '/home',
        exists: (p) async => p == '/home',
        write: (_, _) async {},
        copy: (_) async {},
      );
      expect(await report.save('report'), startsWith('/home/cattunnel-report-'));
    });
  }
  for (final boundary in ['write', 'copy', 'directory']) {
    test('desktop propagates $boundary failure for visible error', () async {
      final report = DesktopReport(
        downloads: () async => '/downloads',
        home: () => null,
        exists: (_) async => boundary != 'directory',
        write: (_, _) async {
          if (boundary == 'write') throw StateError('disk');
        },
        copy: (_) async {
          if (boundary == 'copy') throw StateError('clipboard');
        },
      );
      await expectLater(report.save('report'), throwsStateError);
    });
  }
}
