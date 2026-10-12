import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One hour of one server's tunnel traffic, as counted on this phone.
class TrafficRow {
  /// Start of the hour (local time).
  final DateTime hour;

  /// The app's id of the server that was current then ('' - unknown).
  final String serverId;
  final int rx;
  final int tx;

  const TrafficRow({required this.hour, required this.serverId, required this.rx, required this.tx});

  int get total => rx + tx;
}

/// The phone's own traffic counter (TrafficRecorder.kt on Android): hourly
/// rows per server, nothing leaves the device. Desktop doesn't count yet.
abstract final class TrafficSource {
  static const _channel = MethodChannel('cattunnel/traffic');

  static bool get supported => Platform.isAndroid;

  static Future<List<TrafficRow>> read() async {
    if (!supported) {
      return const [];
    }
    final text = await _channel.invokeMethod<String>('read') ?? '';

    return parse(text);
  }

  /// `hourEpochSec<TAB>serverId<TAB>rx<TAB>tx` lines, summed per hour and
  /// server; malformed lines (a torn last line) are skipped.
  static List<TrafficRow> parse(String text) {
    final sums = <(int, String), List<int>>{};
    for (final line in text.split('\n')) {
      final parts = line.split('\t');
      if (parts.length != 4) {
        continue;
      }
      final hour = int.tryParse(parts[0]);
      final rx = int.tryParse(parts[2]);
      final tx = int.tryParse(parts[3]);
      if (hour == null || rx == null || tx == null || rx < 0 || tx < 0) {
        continue;
      }
      final sum = sums.putIfAbsent((hour, parts[1]), () => [0, 0]);
      sum[0] += rx;
      sum[1] += tx;
    }

    return [
      for (final MapEntry(key: (hour, server), value: sum) in sums.entries)
        TrafficRow(
          hour: DateTime.fromMillisecondsSinceEpoch(hour * 1000),
          serverId: server,
          rx: sum[0],
          tx: sum[1],
        ),
    ]..sort((a, b) => a.hour.compareTo(b.hour));
  }
}

/// The person's own monthly limit (0 - none), for the "this month" bar.
abstract final class TrafficLimit {
  static const _key = 'traffic_monthly_limit_bytes';

  static int get(SharedPreferences preferences) => preferences.getInt(_key) ?? 0;

  static Future<void> set(SharedPreferences preferences, int bytes) =>
      bytes > 0 ? preferences.setInt(_key, bytes) : preferences.remove(_key);
}

/// Bytes for people: "1,2 ГБ" / "1.2 GB".
String formatBytes(num bytes, {required bool ru, int? fractionDigits}) {
  final units = ru ? const ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'] : const ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  var digits = fractionDigits ?? (unit == 0 || value >= 100 ? 0 : (value >= 10 ? 1 : 2));
  // 1023.99 KB would round to "1024 KB": show it as the next unit.
  if (unit < units.length - 1 && double.parse(value.toStringAsFixed(digits)) >= 1024) {
    value /= 1024;
    unit++;
    digits = fractionDigits ?? 2;
  }
  var number = value.toStringAsFixed(digits);
  if (digits > 0) {
    number = number.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  return '${ru ? number.replaceAll('.', ',') : number} ${units[unit]}';
}

/// "Nice" axis ticks 0..max in the unit [formatBytes] will show them in
/// (1/2/2.5/5 × 10^k), so the axis says "1 ГБ", not "954 МБ".
List<double> niceByteTicks(double max, {int count = 4}) {
  if (max <= 0) {
    return const [0, 1];
  }
  var unit = 1.0;
  while (max / unit >= 1024 && unit < math.pow(1024, 4)) {
    unit *= 1024;
  }
  final scaled = max / unit;
  final raw = scaled / count;
  final pow = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final step = [1, 2, 2.5, 5, 10].map((m) => m * pow).firstWhere((s) => s >= raw, orElse: () => 10 * pow);
  final top = (scaled / step).ceil() * step;

  return [for (var v = 0.0; v <= top + step / 2; v += step) v * unit];
}
