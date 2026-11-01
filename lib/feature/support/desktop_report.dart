import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// OS boundaries are injectable so tests never touch user files or clipboard.
class DesktopReport {
  DesktopReport({
    Future<String?> Function()? downloads,
    String? Function()? home,
    Future<bool> Function(String)? exists,
    Future<void> Function(String, String)? write,
    Future<void> Function(String)? copy,
  }) : _downloads = downloads ?? (() async => (await getDownloadsDirectory())?.path),
       _home = home ?? (() => Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME']),
       _exists = exists ?? ((path) => Directory(path).exists()),
       _write =
           write ??
           ((path, text) async {
             await File(path).writeAsString(text, flush: true);
           }),
       _copy = copy ?? ((text) => Clipboard.setData(ClipboardData(text: text)));

  final Future<String?> Function() _downloads;
  final String? Function() _home;
  final Future<bool> Function(String) _exists;
  final Future<void> Function(String, String) _write;
  final Future<void> Function(String) _copy;

  Future<String> save(String text, {DateTime? now}) async {
    String? directory;
    try {
      directory = await _downloads();
    } on Object {
      // Some desktop providers do not implement Downloads.
    }
    if (directory == null || !await _exists(directory)) directory = _home();
    if (directory == null || !await _exists(directory)) throw StateError('No report directory');
    final stamp = (now ?? DateTime.now()).toIso8601String().replaceAll(':', '-');
    final path = '$directory${Platform.pathSeparator}cattunnel-report-$stamp.txt';
    await _write(path, text);
    await _copy(text);
    return path;
  }

  static Future<void> openFolder(String path) async {
    final folder = File(path).parent.path;
    if (Platform.isWindows) {
      // explorer.exe exits with 1 even when the folder opened, so its code says nothing.
      await Process.start('explorer.exe', [folder], mode: ProcessStartMode.detached);
      return;
    }
    final result = await Process.run('xdg-open', [folder]);
    if (result.exitCode != 0) throw StateError('Folder opener failed');
  }
}
