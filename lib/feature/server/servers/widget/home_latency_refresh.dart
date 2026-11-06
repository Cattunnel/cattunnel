import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/feature/server/servers/controller/server_latency_controller.dart';

/// Shared by every home style. Timers stop for covered routes, inactive tabs
/// and background windows. Uses the existing endpoint TCP tester only.
class HomeLatencyRefresh extends StatefulWidget {
  const HomeLatencyRefresh({
    required this.controller,
    required this.server,
    required this.vpnState,
    required this.child,
    this.now = DateTime.now,
    super.key,
  });

  final ServerLatencyController controller;
  final Server? server;
  final VpnState vpnState;
  final Widget child;
  final DateTime Function() now;

  @override
  State<HomeLatencyRefresh> createState() => _HomeLatencyRefreshState();
}

class _HomeLatencyRefreshState extends State<HomeLatencyRefresh> with WidgetsBindingObserver {
  Timer? _timer;
  DateTime? _lastStarted;

  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _visible => _foreground && TickerMode.of(context) && (ModalRoute.isCurrentOf(context) ?? true);
  bool get _stable => widget.vpnState == VpnState.connected || widget.vpnState == VpnState.disconnected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(HomeLatencyRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.server != widget.server || oldWidget.vpnState != widget.vpnState) {
      _lastStarted = null;
    }
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _schedule();

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_visible || !_stable || widget.server == null) return;
    final last = _lastStarted;
    if (last != null && widget.vpnState != VpnState.connected) return;
    final remaining = last == null ? Duration.zero : const Duration(seconds: 60) - widget.now().difference(last);
    _timer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (!mounted || !_visible || !_stable) return;
      _lastStarted = widget.now();
      unawaited(widget.controller.testServer(widget.server!).catchError((Object _) {}));
      _schedule();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
