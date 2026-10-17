import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Programs for the per-app split on Windows and Linux: what is running now.
///
/// The engine (own build, process_owner.cpp) finds the owner of every new
/// connection and compares the program's file name - `chrome.exe`, `firefox` -
/// with the picked ones, so the list holds file names, not paths. A program
/// that isn't running can be added by name in the screen.
abstract final class DesktopPrograms {
  static bool get supported => Platform.isWindows || Platform.isLinux;

  /// The name the engine matches: the file name, lower-case on Windows.
  static String nameOf(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;

    return Platform.isWindows ? name.toLowerCase() : name;
  }

  /// Running programs as (name, path), one per name, sorted by name. Never
  /// CatTunnel itself or its engine.
  static List<({String name, String path})> running() {
    final paths = Platform.isWindows ? _windowsPaths() : _linuxPaths();
    final byName = <String, String>{};
    for (final path in paths) {
      final name = nameOf(path);
      if (name.isEmpty || _own.contains(name.toLowerCase())) continue;
      byName.putIfAbsent(name, () => path);
    }

    return [for (final e in byName.entries) (name: e.key, path: e.value)]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// A system program (hidden behind "show system" like on Android).
  static bool isSystem(String path) {
    if (Platform.isWindows) {
      final lower = path.toLowerCase();

      return lower.startsWith(r'c:\windows\') || lower.contains(r'\windowsapps\microsoft.');
    }

    return path.startsWith('/usr/lib') ||
        path.startsWith('/usr/libexec') ||
        path.startsWith('/usr/sbin') ||
        path.startsWith('/lib') ||
        path.startsWith('/sbin') ||
        _linuxShells.contains(nameOf(path));
  }

  static const _own = {
    'cattunnel',
    'cattunnel.exe',
    'trusttunnel_client',
    'trusttunnel_client.exe',
    'cattunnel-helper',
  };

  static const _linuxShells = {'bash', 'sh', 'zsh', 'fish', 'dbus-daemon', 'systemd', 'sudo', 'su', 'login', 'sshd'};

  /// `/proc/<pid>/exe` of the processes this user can see.
  static List<String> _linuxPaths() {
    final paths = <String>[];
    final Directory proc;
    try {
      proc = Directory('/proc');
      for (final entry in proc.listSync(followLinks: false)) {
        final pid = entry.path.split('/').last;
        if (pid.isEmpty || int.tryParse(pid) == null) continue;
        try {
          var exe = Link('/proc/$pid/exe').targetSync();
          if (exe.endsWith(' (deleted)')) exe = exe.substring(0, exe.length - ' (deleted)'.length);
          if (exe.startsWith('/')) paths.add(exe);
        } on FileSystemException {
          // Another user's process or a kernel thread.
        }
      }
    } on FileSystemException {
      return paths;
    }

    return paths;
  }

  /// EnumProcesses + QueryFullProcessImageName (no tasklist.exe: a console
  /// started from the GUI app would flash).
  static List<String> _windowsPaths() {
    const maxPids = 8192;
    final paths = <String>[];
    final pids = calloc<Uint32>(maxPids);
    final needed = calloc<Uint32>();
    final buffer = wsalloc(MAX_PATH * 4);
    final length = calloc<Uint32>();
    try {
      if (EnumProcesses(pids, maxPids * sizeOf<Uint32>(), needed) == 0) return paths;
      final count = needed.value ~/ sizeOf<Uint32>();
      for (var i = 0; i < count; i++) {
        final pid = pids[i];
        if (pid == 0 || pid == 4) continue;
        final handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
        if (handle == 0) continue;
        length.value = MAX_PATH * 4;
        if (QueryFullProcessImageName(handle, 0, buffer, length) != 0) {
          paths.add(buffer.toDartString(length: length.value));
        }
        CloseHandle(handle);
      }
    } finally {
      free(pids);
      free(needed);
      free(buffer);
      free(length);
    }

    return paths;
  }
}
