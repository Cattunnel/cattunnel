import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/traffic/traffic_data.dart';
import 'package:trusttunnel/feature/traffic/traffic_dataset.dart';
import 'package:trusttunnel/feature/traffic/traffic_style.dart';

/// Labels and colors the chart views share.
class TrafficChartContext {
  final TrafficDataset data;
  final TrafficStyle style;
  final bool ru;
  final String Function(String seriesId) labelOf;

  const TrafficChartContext({required this.data, required this.style, required this.ru, required this.labelOf});

  Color colorOf(int index, TrafficSeries series) {
    if (series.id == TrafficSeries.othersId) return style.others;
    if (series.id == 'rx') return style.down;
    if (series.id == 'tx') return style.up;

    return style.palette[index % style.palette.length];
  }

  String fmt(num bytes) => formatBytes(bytes, ru: ru);

  static const _weekdaysRu = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  static const _weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String weekday(int index) => (ru ? _weekdaysRu : _weekdaysEn)[index];

  String hourLabel(int hour) => '${hour.toString().padLeft(2, '0')}:00';

  String dayLabel(DateTime day) => ru
      ? '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}'
      : '${day.month.toString().padLeft(2, '0')}/${day.day.toString().padLeft(2, '0')}';

  /// Short x label of bucket [i].
  String xLabel(int i) => switch (data.axis) {
    TrafficAxis.time => data.period.hourly ? hourLabel(data.times[i].hour) : dayLabel(data.times[i]),
    TrafficAxis.hourOfDay => '$i',
    TrafficAxis.weekday => weekday(i),
  };

  /// Full label of bucket [i] for the tooltip and the table.
  String xTitle(int i) => switch (data.axis) {
    TrafficAxis.time =>
      data.period.hourly
          ? '${dayLabel(data.times[i])}, ${hourLabel(data.times[i].hour)}'
          : '${weekday(data.times[i].weekday - 1)}, ${dayLabel(data.times[i])}',
    TrafficAxis.hourOfDay => '${hourLabel(i)}–${hourLabel((i + 1) % 24)}',
    TrafficAxis.weekday => weekday(i),
  };
}

/// The chart in the picked view.
class TrafficChart extends StatelessWidget {
  final TrafficChartContext chart;
  final TrafficView view;

  const TrafficChart({super.key, required this.chart, required this.view});

  @override
  Widget build(BuildContext context) => switch (view) {
    TrafficView.line || TrafficView.columns || TrafficView.area => _XyChart(chart: chart, view: view),
    TrafficView.ranking => _RankingView(chart: chart),
    TrafficView.share => _ShareView(chart: chart),
    TrafficView.heatmap => _HeatmapView(chart: chart),
  };
}

/// Color dots with names under the chart.
class TrafficLegend extends StatelessWidget {
  final TrafficChartContext chart;

  const TrafficLegend({super.key, required this.chart});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 6,
    children: [
      for (final (i, s) in chart.data.series.indexed)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(color: chart.colorOf(i, s)),
            const SizedBox(width: 6),
            Text(chart.labelOf(s.id), style: context.textTheme.bodySmall?.copyWith(color: chart.style.text)),
          ],
        ),
    ],
  );
}

class _Dot extends StatelessWidget {
  final Color color;
  final double size;

  const _Dot({required this.color, this.size = 10});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Line / stacked columns / stacked area over the x buckets; tap or drag
/// to see one bucket's values.
class _XyChart extends StatefulWidget {
  final TrafficChartContext chart;
  final TrafficView view;

  const _XyChart({required this.chart, required this.view});

  @override
  State<_XyChart> createState() => _XyChartState();
}

class _XyChartState extends State<_XyChart> {
  int? _selected;

  @override
  void didUpdateWidget(covariant _XyChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chart.data != widget.chart.data) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final chart = widget.chart;
    final count = chart.data.bucketCount;
    final textStyle =
        context.textTheme.bodySmall?.copyWith(color: chart.style.muted, fontSize: 10.5) ?? const TextStyle();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final painter = _XyPainter(
              chart: chart,
              view: widget.view,
              selected: _selected,
              labelStyle: textStyle,
            );
            void pick(Offset position) {
              final index = painter.indexAt(position, Size(constraints.maxWidth, 220), count);
              if (index != _selected) setState(() => _selected = index);
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => pick(d.localPosition),
              onHorizontalDragUpdate: (d) => pick(d.localPosition),
              child: CustomPaint(size: Size(constraints.maxWidth, 220), painter: painter),
            );
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: _selected == null ? const SizedBox(width: double.infinity) : _Tooltip(chart: chart, index: _selected!),
        ),
      ],
    );
  }
}

class _Tooltip extends StatelessWidget {
  final TrafficChartContext chart;
  final int index;

  const _Tooltip({required this.chart, required this.index});

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final (i, s) in chart.data.series.indexed)
        if (s.values[index] > 0) (chart.colorOf(i, s), chart.labelOf(s.id), s.values[index]),
    ];
    final total = rows.fold(0, (sum, r) => sum + r.$3);
    final text = context.textTheme.bodySmall?.copyWith(color: chart.style.text);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: chart.style.grid.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(math.min(chart.style.radius, 12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(chart.xTitle(index), style: text?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (rows.isEmpty) Text('—', style: text),
          for (final (color, label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  _Dot(color: color, size: 8),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(label, style: text, overflow: TextOverflow.ellipsis),
                  ),
                  Text(chart.fmt(value), style: text),
                ],
              ),
            ),
          if (rows.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(context.ln.trafficTotal, style: text?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  Text(chart.fmt(total), style: text?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _XyPainter extends CustomPainter {
  final TrafficChartContext chart;
  final TrafficView view;
  final int? selected;
  final TextStyle labelStyle;

  _XyPainter({required this.chart, required this.view, required this.selected, required this.labelStyle});

  static const _bottom = 20.0;
  static const _top = 6.0;

  bool get _stacked => view != TrafficView.line;

  double _left(List<double> ticks) {
    var width = 0.0;
    for (final t in ticks) {
      width = math.max(width, _text(chart.fmt(t)).width);
    }

    return width + 8;
  }

  TextPainter _text(String s, [TextStyle? style]) => TextPainter(
    text: TextSpan(text: s, style: style ?? labelStyle),
    textDirection: TextDirection.ltr,
  )..layout();

  List<double> _ticks(int count) {
    var max = 0;
    for (var i = 0; i < count; i++) {
      if (_stacked) {
        max = math.max(max, chart.data.series.fold(0, (sum, s) => sum + s.values[i]));
      } else {
        for (final s in chart.data.series) {
          max = math.max(max, s.values[i]);
        }
      }
    }

    return niceByteTicks(max.toDouble());
  }

  int? indexAt(Offset position, Size size, int count) {
    final left = _left(_ticks(count));
    final width = size.width - left;
    if (position.dx < left - 8 || width <= 0) return null;

    return ((position.dx - left) / width * count).floor().clamp(0, count - 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final data = chart.data;
    final count = data.bucketCount;
    final ticks = _ticks(count);
    final top = ticks.last <= 0 ? 1.0 : ticks.last;
    final left = _left(ticks);
    final plot = Rect.fromLTRB(left, _top, size.width, size.height - _bottom);
    final step = plot.width / count;
    double y(num v) => plot.bottom - v / top * plot.height;
    double xCenter(int i) => plot.left + step * (i + 0.5);

    final gridPaint = Paint()
      ..color = chart.style.grid
      ..strokeWidth = 1;
    for (final t in ticks) {
      final yy = y(t);
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), gridPaint);
      final label = _text(chart.fmt(t));
      label.paint(canvas, Offset(left - 8 - label.width, yy - label.height / 2));
    }

    // X labels: as many as fit with ~44 px between them.
    final every = math.max(1, (44 / step).ceil());
    for (var i = 0; i < count; i += every) {
      final label = _text(chart.xLabel(i));
      label.paint(canvas, Offset(xCenter(i) - label.width / 2, plot.bottom + 4));
    }

    if (selected != null) {
      final band = Paint()..color = chart.style.grid.withValues(alpha: 0.5);
      canvas.drawRect(Rect.fromLTWH(plot.left + step * selected!, plot.top, step, plot.height), band);
    }

    final series = data.series;
    switch (view) {
      case TrafficView.columns:
        final base = List.filled(count, 0);
        final width = math.max(1.0, step * 0.7);
        for (final (si, s) in series.indexed) {
          final paint = Paint()..color = chart.colorOf(si, s);
          for (var i = 0; i < count; i++) {
            final v = s.values[i];
            if (v == 0) continue;
            final rect = Rect.fromLTRB(xCenter(i) - width / 2, y(base[i] + v), xCenter(i) + width / 2, y(base[i]));
            final last = si == series.length - 1 || series.skip(si + 1).every((o) => o.values[i] == 0);
            canvas.drawRRect(
              RRect.fromRectAndCorners(
                rect,
                topLeft: last ? const Radius.circular(3) : Radius.zero,
                topRight: last ? const Radius.circular(3) : Radius.zero,
              ),
              paint,
            );
            base[i] += v;
          }
        }
      case TrafficView.area:
        final base = List.filled(count, 0);
        for (final (si, s) in series.indexed) {
          final color = chart.colorOf(si, s);
          final upper = [for (var i = 0; i < count; i++) Offset(xCenter(i), y(base[i] + s.values[i]))];
          final lower = [for (var i = count - 1; i >= 0; i--) Offset(xCenter(i), y(base[i]))];
          final fill = Path()..addPolygon([...upper, ...lower], true);
          canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.35));
          canvas.drawPath(
            Path()..addPolygon(upper, false),
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.8,
          );
          for (var i = 0; i < count; i++) {
            base[i] += s.values[i];
          }
        }
      default:
        for (final (si, s) in series.indexed) {
          final color = chart.colorOf(si, s);
          final points = [for (var i = 0; i < count; i++) Offset(xCenter(i), y(s.values[i]))];
          canvas.drawPath(
            Path()..addPolygon(points, false),
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.2
              ..strokeJoin = StrokeJoin.round,
          );
          if (selected != null) {
            canvas.drawCircle(points[selected!], 3.5, Paint()..color = color);
          }
        }
    }
  }

  @override
  bool shouldRepaint(covariant _XyPainter old) =>
      old.chart.data != chart.data || old.view != view || old.selected != selected || old.chart.style != chart.style;
}

/// One bar per series, length = its total.
class _RankingView extends StatelessWidget {
  final TrafficChartContext chart;

  const _RankingView({required this.chart});

  @override
  Widget build(BuildContext context) {
    final series = chart.data.series;
    final max = series.fold(0, (m, s) => math.max(m, s.total));
    final text = context.textTheme.bodyMedium?.copyWith(color: chart.style.text);

    return Column(
      children: [
        for (final (i, s) in series.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(chart.labelOf(s.id), style: text, overflow: TextOverflow.ellipsis),
                    ),
                    Text(chart.fmt(s.total), style: text?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 4),
                _Bar(
                  fraction: max == 0 ? 0 : s.total / max,
                  color: chart.colorOf(i, s),
                  track: chart.style.grid,
                  height: 12,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final double fraction;
  final Color color;
  final Color track;
  final double height;

  const _Bar({required this.fraction, required this.color, required this.track, required this.height});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height / 2),
    child: Stack(
      children: [
        Container(height: height, color: track),
        FractionallySizedBox(
          widthFactor: fraction.clamp(0, 1),
          child: Container(height: height, color: color),
        ),
      ],
    ),
  );
}

/// One 100 % strip, then the list with proportional bars. No pie charts.
class _ShareView extends StatelessWidget {
  final TrafficChartContext chart;

  const _ShareView({required this.chart});

  @override
  Widget build(BuildContext context) {
    final series = chart.data.series;
    final total = series.fold(0, (sum, s) => sum + s.total);
    final text = context.textTheme.bodyMedium?.copyWith(color: chart.style.text);
    String percent(int v) => total == 0 ? '0' : (v / total * 100).toStringAsFixed(v / total < 0.1 ? 1 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            height: 18,
            child: Row(
              children: [
                for (final (i, s) in series.indexed)
                  if (s.total > 0)
                    Expanded(
                      flex: math.max(1, (s.total * 1000 / total).round()),
                      child: Container(color: chart.colorOf(i, s)),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final (i, s) in series.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _Dot(color: chart.colorOf(i, s)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(chart.labelOf(s.id), style: text, overflow: TextOverflow.ellipsis),
                    ),
                    Text('${percent(s.total)} %', style: text?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 72,
                      child: Text(
                        chart.fmt(s.total),
                        textAlign: TextAlign.right,
                        style: text?.copyWith(color: chart.style.muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                _Bar(
                  fraction: total == 0 ? 0 : s.total / total,
                  color: chart.colorOf(i, s),
                  track: chart.style.grid,
                  height: 4,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 7 weekdays x 24 hours, one hue; opacity = square root of the share of
/// the busiest cell. Tap a cell for its value.
class _HeatmapView extends StatefulWidget {
  final TrafficChartContext chart;

  const _HeatmapView({required this.chart});

  @override
  State<_HeatmapView> createState() => _HeatmapViewState();
}

class _HeatmapViewState extends State<_HeatmapView> {
  (int, int)? _selected;

  static const _labelWidth = 28.0;

  @override
  Widget build(BuildContext context) {
    final chart = widget.chart;
    final heat = chart.data.heat;
    final max = heat.expand((r) => r).fold(0, math.max);
    final small = context.textTheme.bodySmall?.copyWith(color: chart.style.muted, fontSize: 10);
    final text = context.textTheme.bodySmall?.copyWith(color: chart.style.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cell = (constraints.maxWidth - _labelWidth) / 24;
            final height = cell * 7 + 16;
            (int, int)? at(Offset p) {
              final col = ((p.dx - _labelWidth) / cell).floor();
              final row = (p.dy / cell).floor();
              if (col < 0 || col > 23 || row < 0 || row > 6) return null;

              return (row, col);
            }

            return GestureDetector(
              onTapDown: (d) => setState(() => _selected = at(d.localPosition)),
              child: CustomPaint(
                size: Size(constraints.maxWidth, height),
                painter: _HeatPainter(
                  heat: heat,
                  max: max,
                  color: chart.style.heat,
                  empty: chart.style.grid.withValues(alpha: 0.4),
                  selected: _selected,
                  weekday: chart.weekday,
                  labelStyle: small ?? const TextStyle(),
                  labelWidth: _labelWidth,
                ),
              ),
            );
          },
        ),
        if (_selected != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${chart.weekday(_selected!.$1)}, ${chart.hourLabel(_selected!.$2)} — ${chart.fmt(heat[_selected!.$1][_selected!.$2])}',
              style: text,
            ),
          ),
      ],
    );
  }
}

class _HeatPainter extends CustomPainter {
  final List<List<int>> heat;
  final int max;
  final Color color;
  final Color empty;
  final (int, int)? selected;
  final String Function(int) weekday;
  final TextStyle labelStyle;
  final double labelWidth;

  _HeatPainter({
    required this.heat,
    required this.max,
    required this.color,
    required this.empty,
    required this.selected,
    required this.weekday,
    required this.labelStyle,
    required this.labelWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cell = (size.width - labelWidth) / 24;
    for (var row = 0; row < 7; row++) {
      final label = TextPainter(
        text: TextSpan(text: weekday(row), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(0, row * cell + (cell - label.height) / 2));
      for (var col = 0; col < 24; col++) {
        final v = heat[row][col];
        final rect = Rect.fromLTWH(labelWidth + col * cell + 1, row * cell + 1, cell - 2, cell - 2);
        final paint = Paint()
          ..color = v == 0 || max == 0 ? empty : color.withValues(alpha: 0.15 + 0.85 * math.sqrt(v / max));
        canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.18)), paint);
        if (selected == (row, col)) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect.inflate(1), Radius.circular(cell * 0.18)),
            Paint()
              ..color = labelStyle.color ?? Colors.grey
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      }
    }
    for (final hour in [0, 6, 12, 18]) {
      final label = TextPainter(
        text: TextSpan(text: '$hour', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(labelWidth + hour * cell + 1, 7 * cell + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _HeatPainter old) =>
      old.heat != heat || old.selected != selected || old.color != color || old.max != max;
}

/// Rows = buckets (or series for ranking/share), columns = series.
class TrafficValuesTable extends StatelessWidget {
  final TrafficChartContext chart;
  final TrafficView view;

  const TrafficValuesTable({super.key, required this.chart, required this.view});

  @override
  Widget build(BuildContext context) {
    final data = chart.data;
    final text = context.textTheme.bodySmall?.copyWith(color: chart.style.text);
    final head = text?.copyWith(fontWeight: FontWeight.w600);
    final series = data.allSeries;

    Widget cell(String s, {TextStyle? style, bool right = true}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Text(s, style: style ?? text, textAlign: right ? TextAlign.right : TextAlign.left),
    );

    final Table table;
    if (view == TrafficView.ranking || view == TrafficView.share || view == TrafficView.heatmap) {
      final total = data.total;
      table = Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        children: [
          TableRow(
            children: [
              cell('', style: head, right: false),
              cell(context.ln.trafficTotal, style: head),
              cell('%', style: head),
            ],
          ),
          for (final s in series)
            TableRow(
              children: [
                cell(chart.labelOf(s.id), right: false),
                cell(chart.fmt(s.total)),
                cell(total == 0 ? '0' : (s.total / total * 100).toStringAsFixed(1)),
              ],
            ),
        ],
      );
    } else {
      table = Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        children: [
          TableRow(
            children: [
              cell('', style: head, right: false),
              for (final s in series) cell(chart.labelOf(s.id), style: head),
              if (series.length > 1) cell(context.ln.trafficTotal, style: head),
            ],
          ),
          for (var i = 0; i < data.bucketCount; i++)
            TableRow(
              children: [
                cell(chart.xTitle(i), right: false),
                for (final s in series) cell(s.values[i] == 0 ? '—' : chart.fmt(s.values[i])),
                if (series.length > 1) cell(chart.fmt(series.fold(0, (sum, s) => sum + s.values[i])), style: head),
              ],
            ),
        ],
      );
    }

    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: table);
  }
}
