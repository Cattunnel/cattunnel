import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/feature/security/domain/desktop_system_settings.dart';

void main() {
  for (final date in [false, true]) {
    test('Windows opens the fixed ${date ? 'date' : 'network'} URI without shell', () async {
      expect(
        await DesktopSystemSettings.open(
          date: date,
          os: 'windows',
          run: (command, args) async {
            expect(command, 'rundll32.exe');
            expect(args, [
              'url.dll,FileProtocolHandler',
              date ? 'ms-settings:dateandtime' : 'ms-settings:network-status',
            ]);
            return ProcessResult(1, 0, '', '');
          },
        ),
        isTrue,
      );
    });
    test('Linux tries another desktop after a missing command', () async {
      final attempts = <String>[];
      expect(
        await DesktopSystemSettings.open(
          date: date,
          os: 'linux',
          run: (command, args) async {
            attempts.add(command);
            if (command == 'gnome-control-center') throw const ProcessException('gnome-control-center', []);
            expect(args, [date ? 'kcm_clock' : 'kcm_networkmanagement']);
            return ProcessResult(1, 0, '', '');
          },
        ),
        isTrue,
      );
      expect(attempts, ['gnome-control-center', 'systemsettings']);
    });
    test('all opener failures return false for a visible manual hint', () async {
      expect(
        await DesktopSystemSettings.open(date: date, os: 'linux', run: (_, _) async => ProcessResult(1, 1, '', '')),
        isFalse,
      );
      expect(
        await DesktopSystemSettings.open(date: date, os: 'windows', run: (_, _) async => throw StateError('denied')),
        isFalse,
      );
    });
  }
}
