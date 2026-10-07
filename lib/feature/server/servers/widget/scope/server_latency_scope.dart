import 'package:flutter/widgets.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/feature/server/servers/controller/server_latency_controller.dart';

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

  @override
  void initState() {
    super.initState();
    _controller = ServerLatencyController(
      timeoutRepository: context.repositoryFactory.serverTestTimeoutRepository,
    );
  }

  @override
  void dispose() {
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
