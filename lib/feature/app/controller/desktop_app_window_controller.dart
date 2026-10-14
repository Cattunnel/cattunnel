import 'dart:async';

import 'package:adguard_logger/adguard_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:trusttunnel/feature/app/controller/app_window_controller.dart';
import 'package:window_manager/window_manager.dart';

/// Windows and Linux: the close button hides the window to the tray, "Quit"
/// in the tray menu exits. On Windows the VPN engine lives in the app's
/// process, so closing the app would drop the tunnel. On Linux without a
/// tray host (plain GNOME) the window closes as before - hidden, it would
/// be lost; the helper keeps the VPN either way.
final class DesktopAppWindowController with WindowListener implements AppWindowController {
  DesktopAppWindowController()
    : assert(
        defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux,
        'DesktopAppWindowController is only supported on Windows and Linux',
      );

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
    logger.logInfo('window: close goes to the tray', additionalTags: ['window']);
  }

  @override
  void onWindowClose() {
    logger.logInfo('window close: tray=${LinuxSniTrayApi.available}', additionalTags: ['window']);
    if (defaultTargetPlatform == TargetPlatform.linux && !LinuxSniTrayApi.available) {
      unawaited(setPreventClose(false).then((_) => windowManager.close()));

      return;
    }
    hideMainWindow().ignore();
  }
}
