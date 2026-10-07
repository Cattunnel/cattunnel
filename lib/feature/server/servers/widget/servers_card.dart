import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/server_details_popup.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_connection_actions.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_latency_result.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/server_latency_scope.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope_aspect.dart';
import 'package:trusttunnel/feature/server/servers/widget/servers_card_connection_button.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';
import 'package:trusttunnel/widgets/common/custom_list_tile_separated.dart';

class ServersCard extends StatefulWidget {
  final Server server;

  /// Whether to show the last measured latency next to the connect button -
  /// only meaningful (and only shown) while the list is sorted by latency.
  final bool showLatencyBadge;

  const ServersCard({
    super.key,
    required this.server,
    this.showLatencyBadge = false,
  });

  @override
  State<ServersCard> createState() => _ServersCardState();
}

class _ServersCardState extends State<ServersCard> {
  late VpnState _vpnStatus;
  late Server? _pickedServer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _vpnStatus = VpnScope.vpnControllerOf(context).state;
    _pickedServer = ServersScope.controllerOf(
      context,
      aspect: ServersScopeAspect.selectedServer,
    ).selectedServer;

    final isThisServerConnected = _pickedServer?.id == widget.server.id && _vpnStatus == VpnState.connected;

    if (isThisServerConnected) {
      // A live successful connection is itself proof of reachability -
      // clear any stale "unreachable" mark from an earlier test. Deferred to
      // after this build so it doesn't trigger a rebuild mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ServerLatencyScope.of(context, listen: false).clearResult(widget.server.id);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final latencyScope = ServerLatencyScope.of(context);
    final vpnManagerState = _pickedServer?.id == widget.server.id ? _vpnStatus : VpnState.disconnected;
    final latencyResult = latencyScope.resultFor(widget.server.id);
    final isUnreachable = latencyResult != null && !latencyResult.reachable && vpnManagerState != VpnState.connected;

    final baseSubtitle = widget.server.serverData.ipAddress;

    return CustomListTileSeparated(
      title: widget.server.serverData.name,
      titleStyle: context.textTheme.titleSmall,
      subtitle: isUnreachable ? '$baseSubtitle · ${context.ln.serverUnreachable}' : baseSubtitle,
      subtitleStyle: isUnreachable ? context.textTheme.bodySmall?.copyWith(color: context.colors.orange1) : null,
      onTileTap: () => _pushServerDetailsScreen(
        context,
        server: widget.server,
      ),
      contentTrailing: widget.showLatencyBadge
          ? Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _LatencyBadge(
                result: latencyResult,
                isTesting: latencyScope.isTesting(widget.server.id),
              ),
            )
          : null,
      trailing: ServersCardConnectionButton(
        vpnManagerState: vpnManagerState,
        onPressed: () {
          if (_pickedServer?.id == null) {
            ServerConnectionActions.connect(context, widget.server);

            return;
          }

          if (widget.server.id == _pickedServer?.id) {
            if (vpnManagerState != VpnState.disconnected) {
              ServerConnectionActions.disconnect(context);
            } else {
              ServerConnectionActions.connect(context, widget.server);
            }
          } else {
            _changeServer(context, widget.server.id);
          }
        },
        serverId: widget.server.id,
      ),
    );
  }

  void _changeServer(BuildContext context, String? serverId) {
    final controller = ServersScope.controllerOf(context, listen: false);

    controller.pickServer(serverId);
  }

  void _pushServerDetailsScreen(
    BuildContext context, {
    required Server server,
  }) => context.push(
    ServerDetailsPopUp(
      serverId: server.id,
    ),
  );
}

/// Compact latency indicator shown next to the connect button. Only relevant
/// while the list is sorted by latency (see [ServersCard.showLatencyBadge]).
class _LatencyBadge extends StatelessWidget {
  final ServerLatencyResult? result;
  final bool isTesting;

  const _LatencyBadge({
    required this.result,
    required this.isTesting,
  });

  @override
  Widget build(BuildContext context) {
    if (isTesting) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final result = this.result;
    if (result == null) {
      return const SizedBox.shrink();
    }

    final latency = result.latency;

    return Text(
      latency != null ? '${latency.inMilliseconds}ms' : context.ln.serverUnreachable,
      style: context.textTheme.bodySmall?.copyWith(
        color: latency != null ? context.colors.neutralDark : context.colors.orange1,
      ),
    );
  }
}
