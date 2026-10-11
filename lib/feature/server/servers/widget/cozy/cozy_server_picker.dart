import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/asset_icons.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/theme/own_style.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_sort_option.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_sorting.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/server_latency_scope.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope_aspect.dart';
import 'package:trusttunnel/feature/server/servers/widget/server_sort_sheet.dart';
import 'package:trusttunnel/widgets/aero/aero_widgets.dart';
import 'package:trusttunnel/widgets/custom_icon.dart';
import 'package:trusttunnel/widgets/y2k/y2k_widgets.dart';

/// Bottom sheet of the «Уютный» style: every server with its ping, sorted
/// like the servers list (same saved sort option), "sort" and "test all" on
/// top; returns the chosen server.
///
/// [CozyServerPicker.panel] is the same list as the right half of the wide
/// (desktop) window: always open, a tap picks, "⋯" opens the details, "+"
/// adds servers.
class CozyServerPicker extends StatefulWidget {
  final String currentId;

  /// Long press on a server (or "⋯" in the panel): the sheet closes and this
  /// opens its details (view, edit, share, delete) - what tapping a row does
  /// in the list.
  final ValueChanged<Server> onOpenDetails;

  /// Panel mode: a tap on a server calls this instead of closing a sheet.
  final ValueChanged<Server>? onPick;

  /// Panel mode: the "+" in the header.
  final VoidCallback? onAdd;

  const CozyServerPicker({super.key, required this.currentId, required this.onOpenDetails})
    : onPick = null,
      onAdd = null;

  const CozyServerPicker.panel({
    super.key,
    required this.currentId,
    required this.onOpenDetails,
    required ValueChanged<Server> this.onPick,
    required VoidCallback this.onAdd,
  });

  bool get _panel => onPick != null;

  static Future<Server?> show(
    BuildContext context, {
    required String currentId,
    required ValueChanged<Server> onOpenDetails,
  }) => showModalBottomSheet<Server>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Y2K: the theme's glass sheet with cut corner.
    backgroundColor: context.hasOwnStyle ? null : context.colors.background,
    shape: context.hasOwnStyle
        ? null
        : const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => CozyServerPicker(currentId: currentId, onOpenDetails: onOpenDetails),
  );

  @override
  State<CozyServerPicker> createState() => _CozyServerPickerState();
}

class _CozyServerPickerState extends State<CozyServerPicker> {
  ServerSortOption _sortOption = ServerSortOption.origin;
  List<SubscriptionData> _subscriptions = const [];
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    context.repositoryFactory.serverSortPreferenceRepository.getValue().then((value) {
      if (mounted) setState(() => _sortOption = value);
    });
    context.repositoryFactory.subscriptionRepository.getAllSubscriptions().then((value) {
      if (mounted) setState(() => _subscriptions = value);
    });
  }

  /// Refreshes every subscription now - the "⟳" of the list's subscription
  /// groups; the sheet shows the new servers through ServersScope.
  Future<void> _onRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final repository = context.repositoryFactory.subscriptionRepository;
    var failed = false;
    for (final subscription in _subscriptions) {
      try {
        await repository.refresh(subscription: subscription);
      } catch (_) {
        failed = true;
      }
    }
    if (!mounted) return;
    ServersScope.controllerOf(context, listen: false).fetchServers();
    setState(() => _refreshing = false);
    if (failed) context.showInfoSnackBar(message: context.ln.somethingWentWrongSnackbar);
  }

  Future<void> _onSort() async {
    final option = await ServerSortSheet.show(context, current: _sortOption);
    if (option == null || !mounted) return;

    setState(() => _sortOption = option);
    await context.repositoryFactory.serverSortPreferenceRepository.setValue(option);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final allServers = ServersScope.controllerOf(context, aspect: ServersScopeAspect.servers).servers;
    final servers = sortServers(allServers, _sortOption, ServerLatencyScope.of(context));

    final panel = widget._panel;
    final y2k = context.isY2k;
    final aero = context.isAero;
    final content = Column(
      mainAxisSize: panel ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(24, panel ? 16 : 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: y2k
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Y2kChromeTitle(context.ln.cozyChooseServer.toUpperCase(), size: 15),
                        ),
                      )
                    : Text(context.ln.cozyChooseServer, style: context.textTheme.titleLarge),
              ),
              if (_subscriptions.isNotEmpty)
                _refreshing
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        tooltip: context.ln.cozyRefreshSubscription,
                        icon: Icon(Icons.refresh, size: 24, color: colors.accent),
                        onPressed: _onRefresh,
                      ),
              IconButton(
                tooltip: context.ln.sortByTitle,
                // Own color: the theme's IconButton style is white (made for filled buttons).
                icon: CustomIcon.medium(icon: AssetIcons.sort, color: colors.accent),
                onPressed: _onSort,
              ),
              IconButton(
                tooltip: context.ln.cozyTestAll,
                icon: Icon(Icons.speed_rounded, size: 24, color: colors.accent),
                onPressed: () => ServerLatencyScope.of(context, listen: false).testAll(allServers),
              ),
              if (panel)
                IconButton(
                  tooltip: context.ln.addServers,
                  icon: Icon(Icons.add_rounded, size: 26, color: colors.accent),
                  onPressed: widget.onAdd,
                ),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: !panel,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              for (final (index, server) in servers.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _Y2kEntrance(
                    enabled: y2k,
                    index: index,
                    child: Material(
                      color: y2k
                          ? (server.id == widget.currentId
                                ? Y2kColors.electric.withValues(alpha: 0.2)
                                : Y2kColors.navy.withValues(alpha: 0.55))
                          : (server.id == widget.currentId ? colors.blend : colors.backgroundAdditional),
                      shape: y2k
                          ? y2kCut(
                              12,
                              BorderSide(
                                color: server.id == widget.currentId
                                    ? Y2kColors.glow.withValues(alpha: 0.8)
                                    : Y2kColors.steel.withValues(alpha: 0.25),
                              ),
                            )
                          : RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              // Аэро: the current server is ringed in lime.
                              side: aero && server.id == widget.currentId
                                  ? BorderSide(
                                      color: context.isAeroNight ? AeroColors.limeNight : AeroColors.lime,
                                      width: 2,
                                    )
                                  : BorderSide.none,
                            ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        // Y2K: compact rows, more servers on screen.
                        contentPadding: y2k ? const EdgeInsets.fromLTRB(18, 4, 16, 6) : null,
                        visualDensity: y2k ? VisualDensity.compact : null,
                        onTap: () => panel ? widget.onPick!(server) : Navigator.of(context).pop(server),
                        onLongPress: () {
                          if (!panel) Navigator.of(context).pop();
                          widget.onOpenDetails(server);
                        },
                        title: Text(server.serverData.name, style: context.textTheme.titleSmall),
                        subtitle: y2k
                            ? Y2kMicro(server.serverData.ipAddress, color: Y2kColors.dim)
                            : Text(
                                server.serverData.ipAddress,
                                style: context.textTheme.bodySmall?.copyWith(color: colors.neutralDark),
                              ),
                        trailing: panel
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _Latency(server: server),
                                  IconButton(
                                    tooltip: server.serverData.name,
                                    icon: Icon(Icons.more_horiz_rounded, color: colors.neutralDark),
                                    onPressed: () => widget.onOpenDetails(server),
                                  ),
                                ],
                              )
                            : _Latency(server: server),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!panel)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              context.ln.cozyLongPressHint,
              textAlign: TextAlign.center,
              style: context.textTheme.bodySmall?.copyWith(color: colors.neutralDark),
            ),
          ),
      ],
    );

    if (panel) return content;
    // Y2K: the calm moving backdrop behind the sheet's content.
    final sheet = y2k
        ? Stack(
            children: [
              const Positioned.fill(child: Y2kBackdrop(calm: true, child: SizedBox.shrink())),
              content,
            ],
          )
        : content;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: sheet,
      ),
    );
  }
}

class _Latency extends StatelessWidget {
  final Server server;

  const _Latency({required this.server});

  @override
  Widget build(BuildContext context) {
    final scope = ServerLatencyScope.of(context);
    if (scope.isTesting(server.id)) {
      return const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
    }
    final result = scope.resultFor(server.id);
    if (result == null) return const SizedBox.shrink();
    final ms = result.latency?.inMilliseconds;

    return Text(
      ms != null ? context.ln.cozyPing(ms) : context.ln.serverUnreachable,
      style: context.textTheme.bodySmall?.copyWith(
        color: ms != null ? (context.isY2k ? Y2kColors.glow : context.colors.neutralDark) : context.colors.orange1,
      ),
    );
  }
}

/// Y2K: list rows slide in from the left one after another and light up.
class _Y2kEntrance extends StatelessWidget {
  final bool enabled;
  final int index;
  final Widget child;

  const _Y2kEntrance({required this.enabled, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!enabled || MediaQuery.of(context).disableAnimations) return child;
    // Rows further down start later; past the 10th all come together.
    final delay = math.min(index, 10) * 0.06;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + (delay * 1000).round()),
      curve: Interval(delay / (0.38 + delay), 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset((1 - t) * -28, 0), child: child),
      ),
    );
  }
}
