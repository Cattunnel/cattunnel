import 'package:trusttunnel/feature/traffic/traffic_data.dart';

/// The same controls as the panel's «Статистика» page, minus clients.
enum TrafficPeriod {
  day(1),
  week(7),
  month(30),
  quarter(90)
  ;

  final int days;

  const TrafficPeriod(this.days);

  /// A day is shown by hour, longer periods by day.
  bool get hourly => this == day;
}

/// Series: one per server, or download/upload.
enum TrafficDim { server, direction }

/// X axis: the period itself, or folded onto the hours of a day / weekdays.
enum TrafficAxis { time, hourOfDay, weekday }

enum TrafficSort { volume, name, growth }

enum TrafficView { line, columns, area, ranking, share, heatmap }

class TrafficSeries {
  /// Server id, 'rx'/'tx', or [othersId].
  final String id;
  final List<int> values;

  /// The server ids folded into [othersId].
  final List<String> members;

  const TrafficSeries({required this.id, required this.values, this.members = const []});

  static const othersId = '__others';

  int get total => values.fold(0, (sum, v) => sum + v);
}

/// What the chart draws: x buckets and the series over them.
class TrafficDataset {
  final TrafficPeriod period;
  final TrafficAxis axis;

  /// Bucket starts for [TrafficAxis.time]; hour 0..23 / weekday 0..6
  /// (Monday first) otherwise, see [bucketCount].
  final List<DateTime> times;

  /// At most [maxSeries] (the rest folded into "others"), sorted.
  final List<TrafficSeries> series;

  /// Every series, sorted, for the values table.
  final List<TrafficSeries> allSeries;

  /// Weekday (Mon=0) x hour sums for the heat map.
  final List<List<int>> heat;
  final int total;
  final int rx;
  final int tx;

  /// The same span right before this one (null - nothing counted back then).
  final int? previousTotal;

  /// Busiest bucket of the period (time axis).
  final DateTime? peakTime;
  final int peakValue;

  /// Per-server totals in the period (for the "busiest server" tile).
  final Map<String, int> perServer;

  const TrafficDataset({
    required this.period,
    required this.axis,
    required this.times,
    required this.series,
    required this.allSeries,
    required this.heat,
    required this.total,
    required this.rx,
    required this.tx,
    required this.previousTotal,
    required this.peakTime,
    required this.peakValue,
    required this.perServer,
  });

  static const maxSeries = 6;

  int get bucketCount => switch (axis) {
    TrafficAxis.time => times.length,
    TrafficAxis.hourOfDay => 24,
    TrafficAxis.weekday => 7,
  };

  bool get isEmpty => total == 0;

  static TrafficDataset build({
    required List<TrafficRow> rows,
    required TrafficPeriod period,
    required TrafficDim dim,
    required TrafficAxis axis,
    required TrafficSort sort,
    required String? serverFilter,
    required String Function(String id) labelOf,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final times = <DateTime>[];
    if (period.hourly) {
      final thisHour = DateTime(clock.year, clock.month, clock.day, clock.hour);
      for (var i = 23; i >= 0; i--) {
        times.add(thisHour.subtract(Duration(hours: i)));
      }
    } else {
      final today = DateTime(clock.year, clock.month, clock.day);
      for (var i = period.days - 1; i >= 0; i--) {
        times.add(DateTime(today.year, today.month, today.day - i));
      }
    }
    final start = times.first;
    final end = period.hourly
        ? times.last.add(const Duration(hours: 1))
        : DateTime(times.last.year, times.last.month, times.last.day + 1);
    // Calendar steps, not durations: a DST day is 23 or 25 hours.
    final previousStart = period.hourly
        ? start.subtract(const Duration(hours: 24))
        : DateTime(start.year, start.month, start.day - period.days);

    int timeIndex(DateTime hour) {
      if (period.hourly) {
        return hour.difference(start).inHours;
      }
      final day = DateTime(hour.year, hour.month, hour.day);

      return times.indexWhere((t) => t == day);
    }

    final count = switch (axis) {
      TrafficAxis.time => times.length,
      TrafficAxis.hourOfDay => 24,
      TrafficAxis.weekday => 7,
    };
    final bySeries = <String, List<int>>{};
    final heat = List.generate(7, (_) => List.filled(24, 0));
    final perServer = <String, int>{};
    final perTime = List.filled(times.length, 0);
    var total = 0;
    var rx = 0;
    var tx = 0;
    var previous = 0;
    var anyBefore = false;

    for (final row in rows) {
      if (serverFilter != null && row.serverId != serverFilter) {
        continue;
      }
      if (row.hour.isBefore(start)) {
        anyBefore = true;
        if (!row.hour.isBefore(previousStart)) {
          previous += row.total;
        }
        continue;
      }
      if (!row.hour.isBefore(end)) {
        continue;
      }
      final t = timeIndex(row.hour);
      if (t < 0) {
        continue;
      }
      final bucket = switch (axis) {
        TrafficAxis.time => t,
        TrafficAxis.hourOfDay => row.hour.hour,
        TrafficAxis.weekday => row.hour.weekday - 1,
      };

      void add(String id, int bytes) {
        if (bytes == 0) {
          return;
        }
        bySeries.putIfAbsent(id, () => List.filled(count, 0))[bucket] += bytes;
      }

      if (dim == TrafficDim.server) {
        add(row.serverId, row.total);
      } else {
        add('rx', row.rx);
        add('tx', row.tx);
      }
      heat[row.hour.weekday - 1][row.hour.hour] += row.total;
      perServer[row.serverId] = (perServer[row.serverId] ?? 0) + row.total;
      perTime[t] += row.total;
      total += row.total;
      rx += row.rx;
      tx += row.tx;
    }

    // Growth: each series' second half of the period against its first,
    // whatever the x axis shows.
    final growthBase = <String, double>{};
    if (sort == TrafficSort.growth) {
      final half = times.length ~/ 2;
      for (final row in rows) {
        if ((serverFilter != null && row.serverId != serverFilter) ||
            row.hour.isBefore(start) ||
            !row.hour.isBefore(end)) {
          continue;
        }
        final t = timeIndex(row.hour);
        final sign = t >= half ? 1 : -1;
        final keys = dim == TrafficDim.server ? [(row.serverId, row.total)] : [('rx', row.rx), ('tx', row.tx)];
        for (final (id, bytes) in keys) {
          growthBase[id] = (growthBase[id] ?? 0) + sign * bytes;
        }
      }
    }

    final all = [for (final MapEntry(:key, :value) in bySeries.entries) TrafficSeries(id: key, values: value)];
    int byVolume(TrafficSeries a, TrafficSeries b) => b.total.compareTo(a.total);
    all.sort(switch (sort) {
      TrafficSort.volume => byVolume,
      TrafficSort.name => (a, b) => labelOf(a.id).toLowerCase().compareTo(labelOf(b.id).toLowerCase()),
      TrafficSort.growth => (a, b) => (growthBase[b.id] ?? 0).compareTo(growthBase[a.id] ?? 0),
    });

    var shown = all;
    if (all.length > maxSeries) {
      // The biggest ones stay whatever the order; they keep the sort order.
      final biggest = ([...all]..sort(byVolume)).take(maxSeries - 1).toSet();
      final keep = all.where(biggest.contains).toList();
      final rest = all.where((s) => !biggest.contains(s)).toList();
      final others = List.filled(count, 0);
      for (final s in rest) {
        for (var i = 0; i < count; i++) {
          others[i] += s.values[i];
        }
      }
      shown = [
        ...keep,
        TrafficSeries(id: TrafficSeries.othersId, values: others, members: [for (final s in rest) s.id]),
      ];
    }

    var peakIndex = -1;
    for (var i = 0; i < perTime.length; i++) {
      if (perTime[i] > 0 && (peakIndex < 0 || perTime[i] > perTime[peakIndex])) {
        peakIndex = i;
      }
    }

    return TrafficDataset(
      period: period,
      axis: axis,
      times: times,
      series: shown,
      allSeries: all,
      heat: heat,
      total: total,
      rx: rx,
      tx: tx,
      previousTotal: anyBefore ? previous : null,
      peakTime: peakIndex < 0 ? null : times[peakIndex],
      peakValue: peakIndex < 0 ? 0 : perTime[peakIndex],
      perServer: perServer,
    );
  }

  /// This calendar month's total (all servers), for the limit bar.
  static int monthTotal(List<TrafficRow> rows, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final monthStart = DateTime(clock.year, clock.month);

    return rows.where((r) => !r.hour.isBefore(monthStart)).fold(0, (sum, r) => sum + r.total);
  }
}
