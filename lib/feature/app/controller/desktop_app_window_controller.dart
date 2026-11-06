import 'dart:async';

import 'package:adguard_logger/adguard_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:trusttunnel/feature/app/controller/app_window_controller.dart';
import 'package:window_manager/window_manager.dart';

/// Windows and Linux close requests are handled by TrayMenuScope, where
/// localization, the saved preference and the live VPN state are available.
final class DesktopAppWindowController with WindowListener implements AppWindowController {
  DesktopAppWindowController()
    : assert(
        defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux,
        'DesktopAppWindowController is only supported on Windows and Linux',
      );

  Future<void> Function()? onCloseRequested;
  bool _handlingClose = false;

  @override
  Future<void> showMainWindow() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> hideMainWindow() async => await windowManager.hide();

  @override
  Future<void> setPreventClose(bool preventClose) async => await windowManager.setPreventClose(preventClose);

  /// The runner already sizes and shows the window; here only the close
  /// button is taken over.
  @override
  Future<void> configureMainWindow({
    required Size minimumWindowSize,
    required Size defaultWindowSize,
    required bool isDebugMode,
  }) async {
    await windowManager.ensureInitialized();
    await setPreventClose(true);
    windowManager.addListener(this);
    logger.logInfo('window: close choice enabled', additionalTags: ['window']);
  }

  @override
  void onWindowClose() {
    if (_handlingClose) return;
    final handler = onCloseRequested;
    if (handler == null) return;
    _handlingClose = true;
    unawaited(handler().whenComplete(() => _handlingClose = false));
  }
}
