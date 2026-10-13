import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/traffic/traffic_charts.dart';
import 'package:trusttunnel/feature/traffic/traffic_data.dart';
import 'package:trusttunnel/feature/traffic/traffic_dataset.dart';
import 'package:trusttunnel/feature/traffic/traffic_style.dart';
import 'package:trusttunnel/widgets/custom_alert_dialog.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';
import 'package:trusttunnel/widgets/secure_screen.dart';

/// Settings -> Traffic statistics: the phone's own counter (TrafficSource)
/// shown like the panel's «Статистика» page - period and server filters,
/// tiles, one chart with split / axis / sort and six views, legend, tap
/// tooltip and a values table - plus this month against the person's own
/// limit. Every style draws it on its own cards and colors (TrafficStyle).
class TrafficStatsScreen extends StatefulWidget {
  const TrafficStatsScreen({super.key});

  @override
  State<TrafficStatsScreen> createState() => _TrafficStatsScreenState();
}

class _TrafficStatsScreenState extends State<TrafficStatsScreen> {
  List<TrafficRow>? _rows;
  Object? _error;
  Timer? _refresh;

  TrafficPeriod _period = TrafficPeriod.week;
  String? _server;
  TrafficDim _dim = TrafficDim.server;
  TrafficAxis _axis = TrafficAxis.time;
  TrafficSort _sort = TrafficSort.volume;
  TrafficView _view = TrafficView.columns;

  @override
  void initState() {
    super.initState();
    _load();
    // Live while open: the recorder samples every 30 s.
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await TrafficSource.read();
      if (mounted) setState(() => _rows = rows);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ln = context.ln;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => CustomAlertDialog(
        title: ln.trafficClearTitle,
        content: Text(ln.trafficClearBody),
        actionsBuilder: (spacing) => [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(ln.cancel)),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(ln.trafficClear)),
        ],
      ),
    );
    if (sure != true) return;
    await TrafficSource.clear();
    await _load();
  }

  String _serverName(String id, Map<String, String> names) {
    if (id.isEmpty) return context.ln.trafficNoServer;

    return names[id] ?? context.ln.trafficDeletedServer;
  }

  @override
  Widget build(BuildContext context) {
    final ln = context.ln;
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    final style = TrafficStyle.of(context);
    final names = {
      for (final s in ServersScope.controllerOf(context).servers) s.id: s.serverData.name,
    };
    String labelOf(String id) => switch (id) {
      'rx' => ln.trafficDownload,
      'tx' => ln.trafficUpload,
      TrafficSeries.othersId => ln.trafficOthers,
      _ => _serverName(id, names),
    };

    final rows = _rows;
    final body = rows == null
        ? Center(child: _error == null ? const CircularProgressIndicator() : Text('$_error'))
        : _content(context, rows, style, ru, labelOf, names);

    // No screenshots / Recents thumbnail: when and where the VPN was used.
    return SecureScreen(
      child: ScaffoldWrapper(
        child: Scaffold(
          appBar: CustomAppBar(
            title: ln.trafficStats,
            centerTitle: true,
            leadingIconType: AppBarLeadingIconType.back,
          ),
          body: body,
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    List<TrafficRow> rows,
    TrafficStyle style,
    bool ru,
    String Function(String) labelOf,
    Map<String, String> names,
  ) {
    final ln = context.ln;
    final serverIds = {for (final r in rows) r.serverId}.toList()
      ..sort((a, b) => labelOf(a).toLowerCase().compareTo(labelOf(b).toLowerCase()));
    if (_server != null && !serverIds.contains(_server)) _server = null;

    final data = TrafficDataset.build(
      rows: rows,
      period: _period,
      dim: _dim,
      axis: _axis,
      sort: _sort,
      serverFilter: _server,
      labelOf: labelOf,
    );
    final chart = TrafficChartContext(data: data, style: style, ru: ru, labelOf: labelOf);
    final muted = context.textTheme.bodySmall?.copyWith(color: style.muted);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _MonthCard(rows: rows, style: style, ru: ru, onChanged: () => setState(() {})),
          const SizedBox(height: 12),
          TrafficSegments<TrafficPeriod>(
            items: [
              (TrafficPeriod.day, ln.trafficPeriodDay),
              (TrafficPeriod.week, ln.trafficPeriodWeek),
              (TrafficPeriod.month, ln.trafficPeriodMonth),
              (TrafficPeriod.quarter, ln.trafficPeriodQuarter),
            ],
            selected: _period,
            onChanged: (v) => setState(() => _period = v),
          ),
          if (serverIds.length > 1) ...[
            const SizedBox(height: 10),
            _Picker<String?>(
              label: ln.trafficServer,
              value: _server,
              style: style,
              items: [(null, ln.trafficAllServers), for (final id in serverIds) (id, labelOf(id))],
              onChanged: (v) => setState(() => _server = v),
            ),
          ],
          const SizedBox(height: 12),
          _Tiles(data: data, chart: chart),
          const SizedBox(height: 12),
          TrafficCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(ln.trafficChartTitle, style: context.textTheme.titleMedium?.copyWith(color: style.text)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _Picker<TrafficDim>(
                      label: ln.trafficDim,
                      value: _dim,
                      style: style,
                      items: [(TrafficDim.server, ln.trafficDimServer), (TrafficDim.direction, ln.trafficDimDirection)],
                      onChanged: (v) => setState(() => _dim = v),
                    ),
                    _Picker<TrafficAxis>(
                      label: ln.trafficAxis,
                      value: _axis,
                      style: style,
                      items: [
                        (TrafficAxis.time, ln.trafficAxisTime),
                        (TrafficAxis.hourOfDay, ln.trafficAxisHour),
                        (TrafficAxis.weekday, ln.trafficAxisWeekday),
                      ],
                      onChanged: (v) => setState(() => _axis = v),
                    ),
                    _Picker<TrafficSort>(
                      label: ln.trafficSort,
                      value: _sort,
                      style: style,
                      items: [
                        (TrafficSort.volume, ln.trafficSortVolume),
                        (TrafficSort.name, ln.trafficSortName),
                        (TrafficSort.growth, ln.trafficSortGrowth),
                      ],
                      onChanged: (v) => setState(() => _sort = v),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TrafficSegments<TrafficView>(
                  items: [
                    (TrafficView.line, ln.trafficViewLine),
                    (TrafficView.columns, ln.trafficViewColumns),
                    (TrafficView.area, ln.trafficViewArea),
                    (TrafficView.ranking, ln.trafficViewRanking),
                    (TrafficView.share, ln.trafficViewShare),
                    (TrafficView.heatmap, ln.trafficViewHeatmap),
                  ],
                  selected: _view,
                  onChanged: (v) => setState(() => _view = v),
                ),
                const SizedBox(height: 14),
                if (data.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(ln.trafficEmpty, textAlign: TextAlign.center, style: muted),
                  )
                else ...[
                  if (_view != TrafficView.heatmap && _view != TrafficView.ranking && _view != TrafficView.share) ...[
                    TrafficLegend(chart: chart),
                    const SizedBox(height: 10),
                  ],
                  TrafficChart(chart: chart, view: _view),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(ln.trafficTable, style: context.textTheme.bodyMedium?.copyWith(color: style.text)),
                      iconColor: style.text,
                      collapsedIconColor: style.muted,
                      children: [TrafficValuesTable(chart: chart, view: _view)],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(ln.trafficPrivacyNote, textAlign: TextAlign.center, style: muted),
          if (rows.isNotEmpty)
            Center(
              child: TextButton(onPressed: () => _confirmClear(context), child: Text(ln.trafficClear)),
            ),
        ],
      ),
    );
  }
}

/// A labelled dropdown in the current style's tones.
class _Picker<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final TrafficStyle style;

  const _Picker({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.style,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$label: ', style: context.textTheme.bodySmall?.copyWith(color: style.muted)),
      DropdownButton<T>(
        value: value,
        isDense: true,
        underline: const SizedBox.shrink(),
        style: context.textTheme.bodyMedium?.copyWith(color: style.text),
        dropdownColor: context.colors.backgroundSystem,
        items: [
          for (final (v, text) in items)
            DropdownMenuItem<T>(
              value: v,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(text, overflow: TextOverflow.ellipsis),
              ),
            ),
        ],
        onChanged: (v) => onChanged(v as T),
      ),
    ],
  );
}

class _Tiles extends StatelessWidget {
  final TrafficDataset data;
  final TrafficChartContext chart;

  const _Tiles({required this.data, required this.chart});

  @override
  Widget build(BuildContext context) {
    final ln = context.ln;
    final style = chart.style;

    String? deltaNote;
    Color? deltaColor;
    final previous = data.previousTotal;
    if (previous == null || previous == 0) {
      deltaNote = ln.trafficNoPrevious;
    } else {
      final d = (data.total - previous) / previous;
      final percent = (d.abs() * 100).toStringAsFixed(0);
      deltaNote = d >= 0 ? ln.trafficDeltaUp(percent) : ln.trafficDeltaDown(percent);
      deltaColor = d >= 0 ? style.up : style.down;
    }

    final top = data.perServer.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    final peak = data.peakTime;

    final tiles = [
      _Tile(label: ln.trafficTileTotal, value: chart.fmt(data.total), note: deltaNote, noteColor: deltaColor),
      _Tile(
        label: ln.trafficTileTopServer,
        value: top.isEmpty ? '—' : chart.labelOf(top.first.key),
        note: top.isEmpty || data.total == 0
            ? null
            : '${chart.fmt(top.first.value)} · ${ln.trafficShareOfTotal((top.first.value / data.total * 100).toStringAsFixed(0))}',
      ),
      _Tile(label: ln.trafficTileDirection, value: '↓ ${chart.fmt(data.rx)}', note: '↑ ${chart.fmt(data.tx)}'),
      _Tile(
        label: data.period.hourly ? ln.trafficTilePeakHour : ln.trafficTilePeakDay,
        value: peak == null ? '—' : chart.fmt(data.peakValue),
        note: peak == null
            ? null
            : (data.period.hourly ? '${chart.dayLabel(peak)}, ${chart.hourLabel(peak.hour)}' : chart.dayLabel(peak)),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Rows of equal-height tiles (a long server name wraps its note).
        final columns = constraints.maxWidth >= 720 ? 4 : 2;

        return Column(
          children: [
            for (var i = 0; i < tiles.length; i += columns) ...[
              if (i > 0) const SizedBox(height: 10),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = i; j < i + columns && j < tiles.length; j++) ...[
                      if (j > i) const SizedBox(width: 10),
                      Expanded(child: tiles[j]),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final String? note;
  final Color? noteColor;

  const _Tile({required this.label, required this.value, this.note, this.noteColor});

  @override
  Widget build(BuildContext context) {
    final style = TrafficStyle.of(context);

    return TrafficCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.textTheme.bodySmall?.copyWith(color: style.muted), maxLines: 2),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.titleLarge?.copyWith(color: style.text, fontWeight: FontWeight.w600),
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(
              note!,
              maxLines: 2,
              style: context.textTheme.bodySmall?.copyWith(color: noteColor ?? style.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// This calendar month against the person's own limit.
class _MonthCard extends StatelessWidget {
  final List<TrafficRow> rows;
  final TrafficStyle style;
  final bool ru;
  final VoidCallback onChanged;

  const _MonthCard({required this.rows, required this.style, required this.ru, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final ln = context.ln;
    final preferences = context.dependencyFactory.sharedPreferences;
    final limit = TrafficLimit.get(preferences);
    final used = TrafficDataset.monthTotal(rows);
    final fraction = limit == 0 ? 0.0 : used / limit;
    final barColor = fraction >= 1
        ? style.up
        : (fraction >= 0.8 ? style.palette[2 % style.palette.length] : style.palette.first);
    final text = context.textTheme.bodyMedium?.copyWith(color: style.text);

    return TrafficCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(ln.trafficThisMonth, style: context.textTheme.titleMedium?.copyWith(color: style.text)),
              ),
              TextButton(
                onPressed: () => _editLimit(context, limit),
                child: Text(limit == 0 ? ln.trafficSetLimit : ln.trafficChangeLimit),
              ),
            ],
          ),
          Text(
            limit == 0
                ? formatBytes(used, ru: ru)
                : ln.trafficUsedOf(formatBytes(used, ru: ru), formatBytes(limit, ru: ru)),
            style: context.textTheme.headlineSmall?.copyWith(color: style.text, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (limit == 0)
            Text(ln.trafficNoLimit, style: context.textTheme.bodySmall?.copyWith(color: style.muted))
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction.clamp(0, 1),
                minHeight: 10,
                color: barColor,
                backgroundColor: style.grid,
              ),
            ),
            if (fraction >= 0.8) ...[
              const SizedBox(height: 6),
              Text(fraction >= 1 ? ln.trafficLimitOver : ln.trafficLimitNear, style: text?.copyWith(color: barColor)),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _editLimit(BuildContext context, int current) async {
    final ln = context.ln;
    final preferences = context.dependencyFactory.sharedPreferences;
    final controller = TextEditingController(
      text: current == 0 ? '' : (current / (1 << 30)).toStringAsFixed(current % (1 << 30) == 0 ? 0 : 1),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => CustomAlertDialog(
        title: ln.trafficLimitDialogTitle,
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: ln.trafficLimitGb),
        ),
        actionsBuilder: (spacing) => [
          if (current != 0)
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(0), child: Text(ln.trafficRemoveLimit)),
          TextButton(
            onPressed: () {
              final gb = double.tryParse(controller.text.replaceAll(',', '.').trim());
              Navigator.of(dialogContext).pop(gb == null || gb <= 0 ? 0 : (gb * (1 << 30)).round());
            },
            child: Text(ln.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    await TrafficLimit.set(preferences, result);
    onChanged();
  }
}
