import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Copies a secret (a `tt://` link carries the login and password): marked
/// sensitive on Android (no copy preview, no keyboard clipboard suggestion -
/// SecurityChannel.copySensitive) and cleared after [clearAfter] if nothing
/// else was copied since (audit 13.10 item 4).
abstract final class SensitiveClipboard {
  static const clearAfter = Duration(seconds: 90);
  static const _channel = MethodChannel('cattunnel/security');
  static Timer? _timer;

  static Future<void> copy(String text) async {
    var marked = false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        marked = await _channel.invokeMethod<bool>('copySensitive', text) ?? false;
      } on Object {
        marked = false;
      }
    }
    if (!marked) await Clipboard.setData(ClipboardData(text: text));

    _timer?.cancel();
    _timer = Timer(clearAfter, () => unawaited(_clearIf(text)));
  }

  static Future<void> _clearIf(String text) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Android 10+ lets only the focused app read the clipboard; in the
        // background this does nothing (Android 13 clears it itself later).
        await _channel.invokeMethod<bool>('clearClipboardIf', text);

        return;
      }
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == text) await Clipboard.setData(const ClipboardData(text: ''));
    } on Object {
      // Clipboard unavailable - nothing to clear.
    }
  }
}
