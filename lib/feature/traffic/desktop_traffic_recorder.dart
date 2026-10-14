import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';

/// Windows and Linux counterpart of TrafficRecorder.kt: the bytes of the
/// engine's TUN interface every [_activeEvery] while the VPN is up, kept in
/// the same two files and format (`hourEpochSec<TAB>serverId<TAB>rx<TAB>tx`):
///
/// - `traffic_pending.tsv` - raw samples of the hours not folded yet (small);
/// - `traffic_hourly.tsv` - finished hours, one line per hour and server,
///   appended once an hour and trimmed to [_keepDays] once a day.
///
/// TUN counters are the tunnel's own traffic: rx is what came down to the
/// apps, tx what they sent. Only counted while the app runs - on Linux the
/// VPN can outlive the window, and that time isn't counted.
class DesktopTrafficRecorder {
  static bool get supported => !kIsWeb && (Platform.isWindows || Platform.isLinux);

  static final instance = DesktopTrafficRecorder._();

  static const _activeEvery = Duration(seconds: 30);
  static const _keepDays = 180;
  static const _archiveName = 'traffic_hourly.tsv';
  static const _pendingName = 'traffic_pending.tsv';

  DesktopTrafficRecorder._();

  Timer? _timer;
  bool _active = false;
  String _serverId = '';
  int _lastRx = -1;
  int _lastTx = -1;
  int? _foldedHour;
  int? _trimmedDay;
  Directory? _dir;

  /// Linux: tun devices before the VPN started, to tell ours once it's up.
  Set<String> _tunsBefore = const {};
  String? _linuxTun;

  /// Fed by VpnScope on every state change and server switch.
  void onState(VpnState state, String? serverId) {
    if (!supported) return;
    if (serverId != null) {
      _serverId = _clean(serverId);
    } else if (_serverId.isEmpty) {
      // Unknown here (the app came up with the VPN running): the last server,
      // as on Android.
      unawaited(
        SharedPreferences.getInstance().then((p) {
          if (_serverId.isEmpty) _serverId = _clean(p.getString('auto_connect_on_launch_last_server_id') ?? '');
        }),
      );
    }
    final active = state != VpnState.disconnected;
    if (active == _active) return;
    _active = active;
    if (active) {
      _tunsBefore = Platform.isLinux ? _linuxTuns() : const {};
      _linuxTun = null;
      _lastRx = -1;
      _lastTx = -1;
      _timer ??= Timer.periodic(_activeEvery, (_) => unawaited(_sample()));
    } else {
      // The last stretch before the stop still counts.
      unawaited(
        _sample().whenComplete(() {
          if (!_active) {
            _timer?.cancel();
            _timer = null;
          }
        }),
      );
    }
  }

  static String _clean(String id) => id.replaceAll(RegExp(r'[\t\r\n]'), ' ');

  /// Everything counted so far, archive first.
  Future<String> read() async {
    final dir = await _directory();
    final buffer = StringBuffer();
    for (final name in [_archiveName, _pendingName]) {
      final file = File('${dir.path}/$name');
      if (file.existsSync()) buffer.write(await file.readAsString());
    }

    return buffer.toString();
  }

  Future<void> clear() async {
    final dir = await _directory();
    for (final name in [_archiveName, _pendingName]) {
      final file = File('${dir.path}/$name');
      if (file.existsSync()) await file.delete();
    }
  }

  Future<Directory> _directory() async =>
      _dir ??= await Directory('${(await getApplicationSupportDirectory()).path}/traffic').create(recursive: true);

  Future<void> _sample() async {
    try {
      final counters = _readCounters();
      if (counters == null) return;
      final (rx, tx) = counters;
      final dir = await _directory();
      final hour = _currentHour();
      if (_lastRx >= 0 && rx >= _lastRx && tx >= _lastTx) {
        final dRx = rx - _lastRx;
        final dTx = tx - _lastTx;
        if (dRx + dTx > 0) {
          await File(
            '${dir.path}/$_pendingName',
          ).writeAsString('$hour\t$_serverId\t$dRx\t$dTx\n', mode: FileMode.append);
        }
      }
      _lastRx = rx;
      _lastTx = tx;

      if (hour != _foldedHour && await _foldPending(dir, hour)) _foldedHour = hour;
      final day = hour ~/ 86400;
      if (day != _trimmedDay && await _trimArchive(dir, hour)) _trimmedDay = day;
    } on Object {
      // A missed sample only loses its 30 s; never break the VPN screen.
    }
  }

  static int _currentHour() => DateTime.now().millisecondsSinceEpoch ~/ 1000 ~/ 3600 * 3600;

  (int, int)? _readCounters() {
    if (Platform.isLinux) {
      _linuxTun ??= _pickLinuxTun();
      final tun = _linuxTun;
      if (tun == null) return null;
      final rx = int.tryParse(_readSys('/sys/class/net/$tun/statistics/rx_bytes'));
      final tx = int.tryParse(_readSys('/sys/class/net/$tun/statistics/tx_bytes'));
      if (rx == null || tx == null) {
        _linuxTun = null; // gone (reconnect made a new one)

        return null;
      }

      return (rx, tx);
    }

    return _WindowsTunCounters.read();
  }

  /// The tun that appeared after the start; if the app came up with the VPN
  /// already running, the only tun there is.
  String? _pickLinuxTun() {
    final now = _linuxTuns();
    final appeared = now.difference(_tunsBefore);
    if (appeared.length == 1) return appeared.single;
    if (_tunsBefore.isEmpty && now.length == 1) return now.single;

    return null;
  }

  static Set<String> _linuxTuns() {
    try {
      return {
        for (final entry in Directory('/sys/class/net').listSync())
          if (File('${entry.path}/tun_flags').existsSync()) entry.uri.pathSegments.where((s) => s.isNotEmpty).last,
      };
    } on Object {
      return const {};
    }
  }

  static String _readSys(String path) {
    try {
      return File(path).readAsStringSync().trim();
    } on Object {
      return '';
    }
  }

  static Map<(int, String), List<int>> _readTotals(File file, bool Function(int hour) keep) {
    final totals = <(int, String), List<int>>{};
    if (!file.existsSync()) return totals;
    for (final line in file.readAsLinesSync()) {
      final parts = line.split('\t');
      if (parts.length != 4) continue;
      final hour = int.tryParse(parts[0]);
      final rx = int.tryParse(parts[2]);
      final tx = int.tryParse(parts[3]);
      if (hour == null || rx == null || tx == null || !keep(hour)) continue;
      final sum = totals.putIfAbsent((hour, parts[1]), () => [0, 0]);
      sum[0] += rx;
      sum[1] += tx;
    }

    return totals;
  }

  static String _lines(Map<(int, String), List<int>> totals) =>
      totals.entries.map((e) => '${e.key.$1}\t${e.key.$2}\t${e.value[0]}\t${e.value[1]}\n').join();

  static Future<bool> _write(File file, Map<(int, String), List<int>> totals) async {
    final tmp = File('${file.path}.tmp');
    try {
      await tmp.writeAsString(_lines(totals), flush: true);
      await tmp.rename(file.path);

      return true;
    } on Object {
      if (tmp.existsSync()) await tmp.delete();

      return false;
    }
  }

  /// Finished hours of the pending file go to the archive; the current hour stays.
  static Future<bool> _foldPending(Directory dir, int nowHour) async {
    final pending = File('${dir.path}/$_pendingName');
    if (!pending.existsSync()) return true;
    final finished = _readTotals(pending, (hour) => hour < nowHour);
    if (finished.isNotEmpty) {
      await File('${dir.path}/$_archiveName').writeAsString(_lines(finished), mode: FileMode.append);
    }

    return _write(pending, _readTotals(pending, (hour) => hour >= nowHour));
  }

  /// Once a day: nothing older than [_keepDays], one line per hour and server.
  static Future<bool> _trimArchive(Directory dir, int nowHour) async {
    final archive = File('${dir.path}/$_archiveName');
    if (!archive.existsSync()) return true;
    final oldest = nowHour - _keepDays * 24 * 3600;

    return _write(archive, _readTotals(archive, (hour) => hour >= oldest));
  }
}

/// InOctets/OutOctets of the Wintun adapter (the same match as
/// physical_net.cpp: "wintun" in the description, or "trusttunnel" in the
/// alias or description) via GetIfTable2 - the win32 package doesn't wrap it.
abstract final class _WindowsTunCounters {
  // MIB_IF_ROW2 (netioapi.h), x64: 1352 bytes; the table's rows start at 8.
  static const _rowSize = 1352;
  static const _tableRows = 8;
  static const _aliasOffset = 28;
  static const _descriptionOffset = 542;
  static const _stringChars = 257;
  static const _operStatusOffset = 1156;
  static const _inOctetsOffset = 1208;
  static const _outOctetsOffset = 1280;
  static const _operStatusUp = 1;

  static final _iphlpapi = DynamicLibrary.open('iphlpapi.dll');
  static final _getIfTable2 = _iphlpapi
      .lookupFunction<Uint32 Function(Pointer<Pointer<Uint8>>), int Function(Pointer<Pointer<Uint8>>)>('GetIfTable2');
  static final _freeMibTable = _iphlpapi.lookupFunction<Void Function(Pointer<Uint8>), void Function(Pointer<Uint8>)>(
    'FreeMibTable',
  );

  static (int, int)? read() {
    final out = calloc<Pointer<Uint8>>();
    try {
      if (_getIfTable2(out) != 0) return null;
      final table = out.value;
      try {
        final count = table.cast<Uint32>().value;
        for (var i = 0; i < count; i++) {
          final row = table + _tableRows + i * _rowSize;
          final alias = _string(row + _aliasOffset).toLowerCase();
          final description = _string(row + _descriptionOffset).toLowerCase();
          // Filter drivers (WFP, QoS, Npcap...) show up as extra rows named
          // '<adapter>-<filter>-0000' with the same counters: skip them.
          if (alias.endsWith('-0000')) continue;
          final ours =
              description.contains('wintun') || alias.contains('trusttunnel') || description.contains('trusttunnel');
          if (!ours || (row + _operStatusOffset).cast<Uint32>().value != _operStatusUp) continue;

          return ((row + _inOctetsOffset).cast<Uint64>().value, (row + _outOctetsOffset).cast<Uint64>().value);
        }

        return null;
      } finally {
        _freeMibTable(table);
      }
    } finally {
      calloc.free(out);
    }
  }

  static String _string(Pointer<Uint8> at) {
    final chars = at.cast<Uint16>();
    var length = 0;
    while (length < _stringChars && chars[length] != 0) {
      length++;
    }

    return String.fromCharCodes(chars.asTypedList(length));
  }
}
