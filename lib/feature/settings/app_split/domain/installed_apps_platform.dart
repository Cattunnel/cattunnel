import 'package:flutter/services.dart';
import 'package:trusttunnel/feature/settings/app_split/domain/desktop_programs.dart';

/// An app with a launcher entry, from `cattunnel/apps` (AppsChannel.kt).
class InstalledApp {
  final String packageName;
  final String label;
  final bool isSystem;

  const InstalledApp({required this.packageName, required this.label, required this.isSystem});
}

/// Dart side of `cattunnel/apps` (Android); on Windows and Linux - the
/// running programs (DesktopPrograms), [InstalledApp.packageName] being the
/// file name the engine matches.
class InstalledAppsPlatform {
  static const _channel = MethodChannel('cattunnel/apps');

  const InstalledAppsPlatform._();

  static Future<List<InstalledApp>> list() async {
    if (DesktopPrograms.supported) {
      return [
        for (final p in DesktopPrograms.running())
          InstalledApp(packageName: p.name, label: p.name, isSystem: DesktopPrograms.isSystem(p.path)),
      ];
    }
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('list') ?? const [];

    return [
      for (final app in raw)
        InstalledApp(
          packageName: app['package']! as String,
          label: app['label']! as String,
          isSystem: app['system']! as bool,
        ),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  /// Installed package names only (no labels) - what a connect needs.
  static Future<List<String>> packages() async =>
      await _channel.invokeListMethod<String>('packages') ?? const <String>[];

  /// Android API level (33 = Android 13), 0 if unknown.
  static Future<int> sdkInt() async => _sdkInt ??= await _channel.invokeMethod<int>('sdkInt') ?? 0;
  static int? _sdkInt;

  /// PNG bytes of the app icon, or null if the app is gone.
  static Future<Uint8List?> icon(String packageName, {int size = 96}) => DesktopPrograms.supported
      ? Future.value()
      : _channel.invokeMethod<Uint8List>('icon', {'package': packageName, 'size': size});
}
