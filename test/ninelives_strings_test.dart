import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The XHTTP transport is called NineLives outside (owner 12.11.2026); arb keys
// and engine names keep "xhttp".
void main() {
  for (final lang in ['ru', 'en']) {
    test('$lang: visible transport texts say NineLives, not XHTTP', () {
      final arb = jsonDecode(File('lib/common/localization/arb/intl_$lang.arb').readAsStringSync()) as Map<String, dynamic>;
      final texts = arb.entries
          .where((e) => !e.key.startsWith('@') && (e.key.startsWith('expertXhttp') || e.key.startsWith('helpXhttp')))
          .where((e) => e.key != 'expertXhttpPathHint')
          .map((e) => e.value as String)
          .toList();
      expect(texts, isNotEmpty);
      for (final text in texts) {
        expect(text.contains('XHTTP'), isFalse, reason: text);
      }
      expect(arb['expertXhttpLabel'], contains('NineLives'));
    });
  }
}
