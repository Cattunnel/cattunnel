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
      'Я уже пробовал 5 способов обхода, ни один не прошёл.',
    );
    expect(
      ln.diagAutoFailedPlain(21),
      'Я уже пробовал без обхода и 21 способ обхода, ни один не прошёл.',
    );
  });

  test('a cut counted in a row declines too, and one cut is not "1 times in a row"', () async {
    final ln = await _ru();

    expect(ln.diagEngineCutAfterBytes(1), 'Соединение оборвалось на полпути.');
    expect(ln.diagEngineCutAfterBytes(2), 'Соединение 2 раза подряд обрывалось на одном и том же месте.');
    expect(ln.diagEngineCutAfterBytes(5), 'Соединение 5 раз подряд обрывалось на одном и том же месте.');
    expect(ln.diagEngineCutAfterBytes(22), 'Соединение 22 раза подряд обрывалось на одном и том же месте.');
  });

  test('the single technique has words without numbering', () async {
    final ln = await _ru();

    expect(ln.antiDpiStatusTechniqueSingle, 'Включаю обход…');
  });
}
