import 'dart:io';

/// Fixed commands only. No shell interpolation or user-supplied arguments.
abstract final class DesktopSystemSettings {
  static Future<bool> open({
    required bool date,
    String? os,
    Future<ProcessResult> Function(String, List<String>)? run,
  }) async {
    final platform = os ?? Platform.operatingSystem;
    final commands = switch (platform) {
      'windows' => [
        ['rundll32.exe', 'url.dll,FileProtocolHandler', date ? 'ms-settings:dateandtime' : 'ms-settings:network-status'],
      ],
      'linux' => [
        ['gnome-control-center', date ? 'datetime' : 'network'],
        ['systemsettings', date ? 'kcm_clock' : 'kcm_networkmanagement'],
        ['systemsettings5', date ? 'kcm_clock' : 'kcm_networkmanagement'],
        if (!date) ['nm-connection-editor'],
      ],
      _ => <List<String>>[],
    };
    final process =
        run ??
        ((command, args) async {
          final child = await Process.start(command, args);
          // Settings apps may live for as long as their window. Drain their pipes
          // and accept a running process after a short startup failure window.
          child.stdout.drain<void>();
          child.stderr.drain<void>();
          final code = await child.exitCode.timeout(const Duration(seconds: 2), onTimeout: () => 0);
          return ProcessResult(child.pid, code, '', '');
        });
    for (final command in commands) {
      try {
        if ((await process(command.first, command.sublist(1))).exitCode == 0) return true;
      } on Object {
        // A different Linux desktop may provide the next settings application.
      }
    }
    return false;
  }
}
