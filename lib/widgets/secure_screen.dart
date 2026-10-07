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
class SecureScreen extends StatefulWidget {
  final Widget child;

  const SecureScreen({super.key, required this.child});

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  static const _channel = MethodChannel('cattunnel/secure_screen');
  static int _active = 0;

  @override
  void initState() {
    super.initState();
    if (_active++ == 0) {
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
