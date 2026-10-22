import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/localization/generated/l10n.dart';

Future<AppLocalizations> _ru() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  return AppLocalizations.load(const Locale('ru'));
}

void main() {
  test('Russian counts decline: 1, 2, 5, 11, 21', () async {
    final ln = await _ru();

    expect(ln.antiDpiStatusFailedModes(1), 'Не помогло: пробовал 1 способ обхода');
    expect(ln.antiDpiStatusFailedModes(2), 'Не помогло: пробовал 2 способа обхода');
    expect(ln.antiDpiStatusFailedModes(5), 'Не помогло: пробовал 5 способов обхода');
    expect(ln.antiDpiStatusFailedModes(11), 'Не помогло: пробовал 11 способов обхода');
    expect(ln.antiDpiStatusFailedModes(21), 'Не помогло: пробовал 21 способ обхода');
    expect(
      ln.antiDpiStatusFailedPlain(2),
      'Не помогло: пробовал напрямую и 2 способа обхода',
    );
    expect(
      ln.diagAutoFailedModes(5),
      'Автоматика уже попробовала 5 способов обхода, ни один не прошёл.',
    );
    expect(
      ln.diagAutoFailedPlain(21),
      'Автоматика уже попробовала напрямую и 21 способ обхода, ни один не прошёл.',
    );
  });

  test('the single technique has words without numbering', () async {
    final ln = await _ru();

    expect(ln.antiDpiStatusTechniqueSingle, 'Включаю обход…');
  });
}
