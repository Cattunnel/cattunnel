import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/feature/server/servers/controller/server_latency_controller.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';

/// Global scope exposing one shared [ServerLatencyController].
///
/// Mounted once near the app root (see `main.dart`) rather than inside the
/// Servers screen subtree, so a test triggered from the Subscriptions screen
/// (a separate pushed route) still updates the same results the Servers
/// screen displays after popping back.
class ServerLatencyScope extends StatefulWidget {
  final Widget child;

  const ServerLatencyScope({
    required this.child,
    super.key,
  });

  static ServerLatencyController of(BuildContext context, {bool listen = true}) => listen
      ? context.dependOnInheritedWidgetOfExactType<_InheritedServerLatencyScope>()!.controller
      : (context.getElementForInheritedWidgetOfExactType<_InheritedServerLatencyScope>()!.widget
                as _InheritedServerLatencyScope)
            .controller;

  @override
  State<ServerLatencyScope> createState() => _ServerLatencyScopeState();
}

class _ServerLatencyScopeState extends State<ServerLatencyScope> {
  late final ServerLatencyController _controller;
  late final ValueListenable<VpnState> _vpnState;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _controller = ServerLatencyController(
      timeoutRepository: context.repositoryFactory.serverTestTimeoutRepository,
    );
    _vpnState = VpnScope.vpnControllerOf(context, listen: false).stateListenable;
    _controller.connectionChanged(_vpnState.value, notify: false);
    _vpnState.addListener(_connectionChanged);
  }

  void _connectionChanged() => _controller.connectionChanged(_vpnState.value);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final servers = ServersScope.controllerOf(context);
    final selected = servers.selectedServer ?? (servers.servers.isEmpty ? null : servers.servers.first);
    if (selected?.id != _selectedId) {
      _selectedId = selected?.id;
      _controller.invalidate(notify: false);
    }
  }

  @override
  void dispose() {
    _vpnState.removeListener(_connectionChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, child) => _InheritedServerLatencyScope(
      controller: _controller,
      child: child!,
    ),
    child: widget.child,
  );
}

class _InheritedServerLatencyScope extends InheritedWidget {
  final ServerLatencyController controller;

  const _InheritedServerLatencyScope({
    required this.controller,
    required super.child,
  });

  @override
  bool updateShouldNotify(_InheritedServerLatencyScope oldWidget) => true;
}
