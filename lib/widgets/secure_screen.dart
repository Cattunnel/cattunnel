import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Blocks screenshots, screen recording and the Recents thumbnail
/// (Android FLAG_SECURE, see CatTunnelActivity.kt) while [child] is on screen.
///
/// Only for screens that show keys - a server's QR/link, a subscription's
/// age key or share QR. Not app-wide on purpose: family members screenshot
/// errors to ask for help. Nested instances are counted, so closing one of
/// two stacked secure screens doesn't lift the flag early.
///
/// [allowScreenshots] (Cyber security -> "Block screenshots" off) turns the
/// whole thing off; it is loaded at start-up, see App.
class SecureScreen extends StatefulWidget {
  final Widget child;

  static bool allowScreenshots = false;

  const SecureScreen({super.key, required this.child});

  /// Applies the setting at once, also to a secure screen that is open now
  /// (the Cyber security screen itself is one under the app lock).
  static Future<void> setAllowScreenshots(bool value) async {
    allowScreenshots = value;
    if (_SecureScreenState._active > 0) {
      await _SecureScreenState._setSecure(!value);
    }
  }

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  static const _channel = MethodChannel('cattunnel/secure_screen');
  static int _active = 0;

  @override
  void initState() {
    super.initState();
    if (_active++ == 0 && !SecureScreen.allowScreenshots) {
      unawaited(_setSecure(true));
    }
  }

  @override
  void dispose() {
    if (--_active == 0) {
      unawaited(_setSecure(false));
    }
    super.dispose();
  }

  static Future<void> _setSecure(bool secure) async {
    try {
      await _channel.invokeMethod<void>('setSecure', secure);
    } on MissingPluginException {
      // Not Android - nothing to toggle.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
