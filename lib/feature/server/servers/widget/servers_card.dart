import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/server_details_popup.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_connection_actions.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_latency_result.dart';
import 'package:trusttunnel/feature/server/servers/widget/favorite_star_button.dart';
import 'package:trusttunnel/feature/server/servers/widget/ping_label.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/server_latency_scope.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope_aspect.dart';
import 'package:trusttunnel/feature/server/servers/widget/servers_card_connection_button.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';
import 'package:trusttunnel/widgets/common/custom_list_tile_separated.dart';

class ServersCard extends StatefulWidget {
  final Server server;

  const ServersCard({
    super.key,
    required this.server,
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
  }

  @override
  Widget build(BuildContext context) {
    final ping = ServerLatencyScope.of(context).resultFor(widget.server.id);
    final vpnManagerState = _pickedServer?.id == widget.server.id ? _vpnStatus : VpnState.disconnected;

    final baseSubtitle = widget.server.serverData.subscriptionOverride
        ? '${widget.server.serverData.ipAddress} · ${context.ln.subscriptionDifferent}'
        : widget.server.serverData.ipAddress;

    return CustomListTileSeparated(
      title: widget.server.serverData.name,
      titleStyle: context.textTheme.titleSmall,
      subtitle: baseSubtitle,
      onTileTap: () => _pushServerDetailsScreen(
        context,
        server: widget.server,
      ),
      contentTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ping?.latency != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _PingBadge(result: ping!),
            ),
          FavoriteStarButton(server: widget.server),
        ],
      ),
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

/// The last in-tunnel ping of the server with the age of the measurement.
class _PingBadge extends StatelessWidget {
  final ServerLatencyResult result;

  const _PingBadge({required this.result});

  @override
  Widget build(BuildContext context) {
    final style = context.textTheme.bodySmall?.copyWith(color: context.colors.neutralDark);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('${result.latency!.inMilliseconds} ${context.ln.pingUnit}', style: style),
        Text(pingAgeLabel(context, result.testedAt), style: style),
      ],
    );
  }
}
