import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/feature/traffic/traffic_data.dart';
import 'package:trusttunnel/feature/traffic/traffic_dataset.dart';

const _mb = 1024 * 1024;
const _gb = 1024 * 1024 * 1024;

/// Fixed "now": Tue 13 Oct 2026, 15:30 local.
final _now = DateTime(2026, 10, 13, 15, 30);
final _thisHour = DateTime(2026, 10, 13, 15);

TrafficRow _row(DateTime hour, String server, int rx, [int tx = 0]) =>
    TrafficRow(hour: hour, serverId: server, rx: rx, tx: tx);

String _identity(String id) => id;

TrafficDataset _build({
  List<TrafficRow> rows = const [],
  TrafficPeriod period = TrafficPeriod.day,
  TrafficDim dim = TrafficDim.server,
  TrafficAxis axis = TrafficAxis.time,
  TrafficSort sort = TrafficSort.volume,
  String? server,
  String Function(String id) labelOf = _identity,
}) {
  return TrafficDataset.build(
    rows: rows,
    period: period,
    dim: dim,
    axis: axis,
    sort: sort,
    serverFilter: server,
    labelOf: labelOf,
    now: _now,
  );
}

TrafficSeries _series(TrafficDataset d, String id) => d.series.firstWhere((s) => s.id == id);

void main() {
  group('TrafficSource.parse', () {
    test('sums duplicate hour+server lines', () {
      final rows = TrafficSource.parse('3600\ta\t10\t5\n3600\ta\t1\t2\n');

      expect(rows, hasLength(1));
      expect(rows.single.hour.millisecondsSinceEpoch, 3600000);
      expect(rows.single.serverId, 'a');
      expect(rows.single.rx, 11);
      expect(rows.single.tx, 7);
      expect(rows.single.total, 18);
    });

    test('keeps different servers in the same hour apart', () {
      final rows = TrafficSource.parse('3600\ta\t10\t0\n3600\tb\t20\t0');

      expect(rows, hasLength(2));
      expect({for (final r in rows) r.serverId: r.rx}, {'a': 10, 'b': 20});
    });

    test('skips malformed and torn lines', () {
      final text = [
        '3600\ta\t1\t2', // good
        '7200\ta\t1', // torn: too few fields
        '10800\ta\t1\t2\t3', // too many fields
        'abc\ta\t1\t2', // hour not a number
        '14400\ta\tx\t2', // rx not a number
        '18000\ta\t1\t', // empty tx
        '', // empty line
      ].join('\n');

      final rows = TrafficSource.parse(text);

      expect(rows, hasLength(1));
      expect(rows.single.hour.millisecondsSinceEpoch, 3600000);
      expect(rows.single.rx, 1);
      expect(rows.single.tx, 2);
    });

    test('skips lines with negative counters, keeps the others', () {
      final rows = TrafficSource.parse('3600\ta\t-1\t2\n3600\ta\t5\t-3\n7200\ta\t4\t6');

      expect(rows, hasLength(1));
      expect(rows.single.hour.millisecondsSinceEpoch, 7200000);
      expect(rows.single.rx, 4);
      expect(rows.single.tx, 6);
    });

    test('sorts the result by hour', () {
      final rows = TrafficSource.parse('10800\ta\t1\t1\n3600\tb\t1\t1\n7200\ta\t1\t1');

      expect(rows.map((r) => r.hour.millisecondsSinceEpoch), [3600000, 7200000, 10800000]);
    });

    test('empty text gives no rows', () {
      expect(TrafficSource.parse(''), isEmpty);
    });
  });

  group('formatBytes', () {
    test('ru uses a comma and МБ', () {
      expect(formatBytes(1536, ru: true), '1,5 КБ');
      expect(formatBytes(12.5 * _mb, ru: true), '12,5 МБ');
    });

    test('en uses a dot and MB', () {
      expect(formatBytes(1536, ru: false), '1.5 KB');
      expect(formatBytes(12.5 * _mb, ru: false), '12.5 MB');
    });

    test('bytes are shown without decimals', () {
      expect(formatBytes(0, ru: false), '0 B');
      expect(formatBytes(512, ru: true), '512 Б');
    });

    test('trailing zeros are trimmed', () {
      expect(formatBytes(_mb, ru: false), '1 MB');
      expect(formatBytes(1.1 * 1024, ru: false), '1.1 KB');
      expect(formatBytes(10 * 1024, ru: false), '10 KB');
      expect(formatBytes(150 * _mb, ru: true), '150 МБ');
    });

    test('1.2 GB keeps its one significant decimal', () {
      expect(formatBytes(1.2 * _gb, ru: false), '1.2 GB');
      expect(formatBytes(1.2 * _gb, ru: true), '1,2 ГБ');
    });

    test('fractionDigits overrides the automatic precision', () {
      expect(formatBytes(_mb, ru: false, fractionDigits: 2), '1 MB');
      expect(formatBytes(1500, ru: false, fractionDigits: 0), '1 KB');
    });

    test('stops at TB', () {
      expect(formatBytes(1024 * _gb * 1024, ru: false), '1024 TB');
    });

    test('value that rounds up to 1024 KB should roll over to MB', () {
      expect(formatBytes(1048575, ru: false), '1 MB');
    });
  });

  group('niceByteTicks', () {
    test('max <= 0 gives [0, 1]', () {
      expect(niceByteTicks(0), [0, 1]);
      expect(niceByteTicks(-5), [0, 1]);
    });

    test('always starts at 0 and the last tick reaches max', () {
      for (final max in [0.5, 1.0, 999.0, 1000.0, 1500.0, 5.0 * _mb, 3.7 * _gb, 1.0e12]) {
        final ticks = niceByteTicks(max);

        expect(ticks.first, 0, reason: 'max=$max');
        expect(ticks.last, greaterThanOrEqualTo(max), reason: 'max=$max');
        for (var i = 1; i < ticks.length; i++) {
          expect(ticks[i], greaterThan(ticks[i - 1]), reason: 'max=$max');
        }
      }
    });

    test('ticks are equally spaced', () {
      final ticks = niceByteTicks(3.7 * _gb);
      final step = ticks[1] - ticks[0];

      for (var i = 1; i < ticks.length; i++) {
        expect(ticks[i] - ticks[i - 1], closeTo(step, step * 1e-9));
      }
    });

    test('plain bytes use nice steps', () {
      expect(niceByteTicks(1000), [0, 250, 500, 750, 1000]);
    });

    test('shows MB ticks rather than bytes', () {
      // raw step 1.25 MB -> first nice step >= it is 2 MB, top = 6 MB (>= 5 MB).
      final ticks = niceByteTicks(5.0 * _mb).map((v) => v / _mb).toList();

      expect(ticks, [0, 2, 4, 6]);
    });

    test('shows GB ticks for a 1 GB axis', () {
      final ticks = niceByteTicks(1.0 * _gb).map((v) => v / _gb).toList();

      expect(ticks.last, closeTo(1, 1e-9));
      expect(ticks.length, inInclusiveRange(3, 6));
    });
  });

  group('TrafficDataset.build', () {
    test('hourly day has 24 buckets ending at the current hour', () {
      final d = _build();

      expect(d.times, hasLength(24));
      expect(d.times.first, DateTime(2026, 10, 12, 16));
      expect(d.times.last, _thisHour);
      expect(d.bucketCount, 24);
    });

    test('a row 3 hours ago lands in bucket 20', () {
      final d = _build(rows: [_row(DateTime(2026, 10, 13, 12), 'a', 100, 50)]);
      final s = _series(d, 'a');

      expect(s.values, hasLength(24));
      expect(s.values[20], 150);
      expect(s.total, 150);
      expect(d.times[20], DateTime(2026, 10, 13, 12));
    });

    test('the current hour is the last bucket; the next hour and 25h ago are excluded', () {
      final d = _build(rows: [
        _row(_thisHour, 'a', 1),
        _row(DateTime(2026, 10, 13, 16), 'a', 1000),
        _row(DateTime(2026, 10, 12, 14), 'a', 1000),
      ]);

      expect(_series(d, 'a').values[23], 1);
      expect(d.total, 1);
    });

    test('weekly period has 7 daily buckets from 7 days back to today', () {
      final d = _build(period: TrafficPeriod.week, rows: [
        _row(DateTime(2026, 10, 10, 8), 'a', 5),
        _row(DateTime(2026, 10, 10, 23), 'a', 7),
      ]);

      expect(d.times, hasLength(7));
      expect(d.times.first, DateTime(2026, 10, 7));
      expect(d.times.last, DateTime(2026, 10, 13));
      expect(_series(d, 'a').values[3], 12);
    });

    test('monthly period has 30 daily buckets', () {
      final d = _build(period: TrafficPeriod.month);

      expect(d.times, hasLength(30));
      expect(d.times.first, DateTime(2026, 10, 13 - 29));
      expect(d.times.last, DateTime(2026, 10, 13));
      expect(d.bucketCount, 30);
    });

    test('server filter keeps only that server', () {
      final rows = [
        _row(DateTime(2026, 10, 13, 10), 'a', 100),
        _row(DateTime(2026, 10, 13, 10), 'b', 900),
      ];
      final d = _build(rows: rows, server: 'a');

      expect(d.total, 100);
      expect(d.perServer, {'a': 100});
      expect(d.series.map((s) => s.id), ['a']);
    });

    test('dim direction splits into rx and tx series', () {
      final d = _build(dim: TrafficDim.direction, rows: [
        _row(DateTime(2026, 10, 13, 10), 'a', 10, 5),
        _row(DateTime(2026, 10, 13, 11), 'b', 20, 0),
      ]);

      expect(_series(d, 'rx').total, 30);
      expect(_series(d, 'tx').total, 5);
      expect(d.rx, 30);
      expect(d.tx, 5);
      expect(d.total, 35);
      expect(d.series.map((s) => s.id).toSet(), {'rx', 'tx'});
    });

    test('hourOfDay axis folds days onto 24 hour buckets', () {
      final d = _build(axis: TrafficAxis.hourOfDay, period: TrafficPeriod.week, rows: [
        _row(DateTime(2026, 10, 13, 3), 'a', 10),
        _row(DateTime(2026, 10, 12, 3), 'a', 20),
      ]);

      expect(d.bucketCount, 24);
      expect(_series(d, 'a').values, hasLength(24));
      expect(_series(d, 'a').values[3], 30);
    });

    test('weekday axis has 7 buckets, Monday first', () {
      final d = _build(axis: TrafficAxis.weekday, period: TrafficPeriod.week, rows: [
        _row(DateTime(2026, 10, 13, 10), 'a', 42),
      ]);

      expect(d.bucketCount, 7);
      expect(_series(d, 'a').values, hasLength(7));
      expect(_series(d, 'a').values[DateTime(2026, 10, 13).weekday - 1], 42);
    });

    test('more than 6 servers fold the smallest into othersId', () {
      final rows = [for (var i = 1; i <= 7; i++) _row(DateTime(2026, 10, 13, 10), 's$i', 100 * i)];
      final d = _build(rows: rows);

      expect(d.allSeries, hasLength(7));
      expect(d.series, hasLength(TrafficDataset.maxSeries));
      final others = d.series.last;
      expect(others.id, TrafficSeries.othersId);
      expect(others.members.toSet(), {'s1', 's2'});
      expect(others.total, 300);
      expect(d.series.take(5).map((s) => s.id), ['s7', 's6', 's5', 's4', 's3']);
    });

    test('six servers are not folded', () {
      final rows = [for (var i = 1; i <= 6; i++) _row(DateTime(2026, 10, 13, 10), 's$i', 100 * i)];
      final d = _build(rows: rows);

      expect(d.series, hasLength(6));
      expect(d.series.any((s) => s.id == TrafficSeries.othersId), isFalse);
    });

    // With sort=name the five biggest by volume still stay out of "others".
    test('folding keeps the biggest servers even when sorted by name', () {
      final rows = [for (var i = 0; i < 7; i++) _row(DateTime(2026, 10, 13, 10), 's$i', 100 * (i + 1))];
      final d = _build(rows: rows, sort: TrafficSort.name);

      expect(d.series.map((s) => s.id), contains('s6'));
    });

    test('previousTotal is null when nothing was counted before the window', () {
      final d = _build(rows: [_row(DateTime(2026, 10, 13, 10), 'a', 100)]);

      expect(d.previousTotal, isNull);
    });

    test('previousTotal sums the same span right before the window', () {
      // Window starts 12 Oct 16:00, previous span is 11 Oct 16:00 - 12 Oct 16:00.
      final d = _build(rows: [
        _row(DateTime(2026, 10, 12, 10), 'a', 40, 10), // inside the previous span
        _row(DateTime(2026, 10, 11, 10), 'a', 999), // before the previous span: not summed
      ]);

      expect(d.previousTotal, 50);
    });

    test('previousTotal ignores rows of other servers when filtering', () {
      final d = _build(server: 'a', rows: [_row(DateTime(2026, 10, 12, 18), 'b', 500)]);

      expect(d.previousTotal, isNull);
    });

    test('volume sort is descending by total', () {
      final d = _build(rows: [
        _row(DateTime(2026, 10, 13, 10), 'small', 1),
        _row(DateTime(2026, 10, 13, 10), 'big', 1000),
        _row(DateTime(2026, 10, 13, 10), 'mid', 100),
      ]);

      expect(d.series.map((s) => s.id), ['big', 'mid', 'small']);
    });

    test('name sort is case-insensitive by label', () {
      const labels = {'a': 'Gamma', 'b': 'alpha', 'c': 'Beta'};
      final d = _build(
        sort: TrafficSort.name,
        labelOf: (id) => labels[id]!,
        rows: [
          _row(DateTime(2026, 10, 13, 10), 'a', 1000),
          _row(DateTime(2026, 10, 13, 10), 'b', 1),
          _row(DateTime(2026, 10, 13, 10), 'c', 10),
        ],
      );

      expect(d.allSeries.map((s) => s.id), ['b', 'c', 'a']);
    });

    test('peak is the busiest bucket with its summed value', () {
      final d = _build(rows: [
        _row(DateTime(2026, 10, 13, 10), 'a', 100),
        _row(DateTime(2026, 10, 13, 14), 'a', 200),
        _row(DateTime(2026, 10, 13, 14), 'b', 100),
      ]);

      expect(d.peakTime, DateTime(2026, 10, 13, 14));
      expect(d.peakValue, 300);
    });

    test('peak on a tie is the earliest bucket', () {
      final d = _build(rows: [
        _row(DateTime(2026, 10, 13, 10), 'a', 100),
        _row(DateTime(2026, 10, 13, 14), 'a', 100),
      ]);

      expect(d.peakTime, DateTime(2026, 10, 13, 10));
    });

    test('empty input gives no peak and is empty', () {
      final d = _build();

      expect(d.isEmpty, isTrue);
      expect(d.total, 0);
      expect(d.peakTime, isNull);
      expect(d.peakValue, 0);
      expect(d.series, isEmpty);
      expect(d.previousTotal, isNull);
    });
  });

  group('TrafficDataset.monthTotal', () {
    test('sums rows from the 1st of this month, skipping earlier ones', () {
      final rows = [
        _row(DateTime(2026, 9, 30, 23), 'a', 1000), // previous month
        _row(DateTime(2026, 10, 1), 'a', 1, 2), // first hour of the month
        _row(DateTime(2026, 10, 13, 9), 'b', 10),
      ];

      expect(TrafficDataset.monthTotal(rows, now: _now), 13);
    });

    test('no rows gives 0', () {
      expect(TrafficDataset.monthTotal(const [], now: _now), 0);
    });
  });
}
