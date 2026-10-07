import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

enum UpdateInstallResult { ok, hashMismatch, untrusted, noPermission }

/// Installing a downloaded update. Android: `cattunnel/update`
/// (android/.../UpdateChannel.kt). Windows: the installer from
/// latest-windows.json, checked against its sha256 here (the signed manifest
/// vouches for the hash) and run silently; see [install].
class UpdatePlatform {
  static const _channel = MethodChannel('cattunnel/update');

  /// Inno Setup: no questions, closes and relaunches CatTunnel itself.
  static const _silentSetup = ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'];

  const UpdatePlatform._();

  static Future<List<String>> supportedAbis() async {
    if (Platform.isWindows) return const ['windows-x64'];

    return (await _channel.invokeListMethod<String>('supportedAbis')) ?? const [];
  }

  /// Whether Android lets CatTunnel open the installer ("install unknown
  /// apps" for this app). Asked once, on the first update. Always on Windows.
  static Future<bool> canInstall() async {
    if (Platform.isWindows) return true;

    return (await _channel.invokeMethod<bool>('canInstall')) ?? false;
  }

  static Future<void> openInstallPermission() => _channel.invokeMethod('openInstallPermission');

  /// Checks [path] against [sha256] and installs it. Android also checks our
  /// signing key (`untrusted`: other signer, other package or not newer) and
  /// opens the system installer. Windows starts the installer detached -
  /// the caller stops the VPN first and quits the app right after `ok`.
  static Future<UpdateInstallResult> install({required String path, required String sha256}) async {
    if (Platform.isWindows) {
      final digest = await Sha256().hash(await File(path).readAsBytes());
      final hex = digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      if (hex != sha256.toLowerCase()) return UpdateInstallResult.hashMismatch;
      await Process.start(path, _silentSetup, mode: ProcessStartMode.detached);

      return UpdateInstallResult.ok;
    }

    final result = await _channel.invokeMethod<String>('install', {'path': path, 'sha256': sha256});

    return switch (result) {
      'ok' => UpdateInstallResult.ok,
      'hash_mismatch' => UpdateInstallResult.hashMismatch,
      'untrusted' => UpdateInstallResult.untrusted,
      _ => UpdateInstallResult.noPermission,
    };
  }
}
