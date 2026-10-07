import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/asset_icons.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/router/app_routes.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/feature/companion/widgets/cat_petting_dialog.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/server_details_popup.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_connection_actions.dart';
import 'package:trusttunnel/feature/server/servers/widget/add_server_flow.dart';
import 'package:trusttunnel/feature/server/servers/widget/cozy/cozy_server_picker.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/server_latency_scope.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope_aspect.dart';
import 'package:trusttunnel/feature/server/servers/widget/servers_empty_placeholder.dart';
import 'package:trusttunnel/feature/vpn/widgets/unvalidated_vpn_notice.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';
import 'package:trusttunnel/widgets/buttons/custom_floating_action_button.dart';
import 'package:trusttunnel/widgets/common/scaffold_messenger_provider.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';

/// The Servers tab in the «Уютный» style (AppearancePreferences): a big
/// round connect button with Marsik, the status with a session timer and
/// ping, and a card of the current server that opens [CozyServerPicker].
/// Connecting goes through [ServerConnectionActions], same as the list.
class CozyServersView extends StatefulWidget {
  /// A tt:// link that opened the app: shown as a pre-filled server form
  /// (nothing is saved until the person confirms), like the list style.
  final ServerData? deepLinkData;

  const CozyServersView({super.key, this.deepLinkData});

  @override
  State<CozyServersView> createState() => _CozyServersViewState();
}

class _CozyServersViewState extends State<CozyServersView> {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  /// When the VPN was seen reaching "connected" - the session timer counts
  /// from here (from app start if it was already connected then).
  DateTime? _connectedSince;
  Timer? _ticker;
  String? _pingedServerId;

  @override
  void initState() {
    super.initState();
    final deepLinkData = widget.deepLinkData;
    if (deepLinkData != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pushServerDetailsScreen(preloadedData: deepLinkData);
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _trackSession(VpnState state) {
    if (state == VpnState.connected) {
      if (_connectedSince == null) {
        _connectedSince = DateTime.now();
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
    } else if (state == VpnState.disconnected && _connectedSince != null) {
      _connectedSince = null;
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// Measures the current server once when it becomes current, so the ping
  /// is there without pressing "test all".
  void _pingOnce(Server server) {
    if (_pingedServerId == server.id) return;
    _pingedServerId = server.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ServerLatencyScope.of(context, listen: false).testServer(server);
    });
  }

  @override
  Widget build(BuildContext context) {
    final servers = ServersScope.controllerOf(context, aspect: ServersScopeAspect.servers).servers;
    final picked = ServersScope.controllerOf(context, aspect: ServersScopeAspect.selectedServer).selectedServer;
    final vpnState = VpnScope.vpnControllerOf(context).state;
    final current = picked ?? (servers.isEmpty ? null : servers.first);
    final state = picked != null && current?.id == picked.id ? vpnState : VpnState.disconnected;

    _trackSession(state);
    if (current != null) _pingOnce(current);

    return ScaffoldWrapper(
      child: ScaffoldMessenger(
        key: _scaffoldMessengerKey,
        child: Scaffold(
          appBar: const CustomAppBar(title: 'CatTunnel'),
          body: current == null
              ? const ServersEmptyPlaceholder()
              : context.isMobileBreakpoint
              ? ListView(
                  // Room for the bottom buttons, which grow with the font.
                  padding: EdgeInsets.fromLTRB(24, 16, 24, 72 + 48 * MediaQuery.textScalerOf(context).scale(1)),
                  children: [
                    Center(
                      child: _ConnectButton(
                        state: state,
                        onTap: () => _onConnectTap(context, current, state),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _StatusBlock(
                      state: state,
                      connectedSince: _connectedSince,
                      server: current,
                    ),
                    const SizedBox(height: 24),
                    _CurrentServerCard(
                      server: current,
                      onTap: () => _openPicker(context, servers, current, state),
                    ),
                  ],
                )
              // Wide (desktop) window: Marsik and the status on the left, the
              // server list always open on the right. Narrower than 600 px
              // it's the phone layout above.
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ConnectButton(
                                    state: state,
                                    size: 260,
                                    onTap: () => _onConnectTap(context, current, state),
                                  ),
                                  const SizedBox(height: 28),
                                  _StatusBlock(
                                    state: state,
                                    connectedSince: _connectedSince,
                                    server: current,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Positioned(left: 16, bottom: 16, child: CatPettingButton()),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 16, 16),
                      child: SizedBox(
                        width: (MediaQuery.sizeOf(context).width * 0.38).clamp(320.0, 480.0),
                        child: Material(
                          color: context.colors.backgroundSystem,
                          borderRadius: BorderRadius.circular(28),
                          clipBehavior: Clip.antiAlias,
                          child: CozyServerPicker.panel(
                            currentId: current.id,
                            onOpenDetails: (server) => _openServerDetails(context, server),
                            onPick: (server) => _switchTo(context, server, current, state),
                            onAdd: () => presentAddServerFlow(context, pushServerDetails: _pushServerDetailsScreen),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
          // Wide window: the petting button sits under Marsik, "+" is in the
          // server panel.
          floatingActionButton: current != null && !context.isMobileBreakpoint
              ? null
              : SizedBox(
                  width: double.infinity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 16),
                        child: CatPettingButton(),
                      ),
                      // Shrinks instead of pushing the cat off screen with a
                      // large system font.
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12, right: 16),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: CustomFloatingActionButton.extended(
                              icon: AssetIcons.add,
                              onPressed: () =>
                                  presentAddServerFlow(context, pushServerDetails: _pushServerDetailsScreen),
                              label: context.ln.addServers,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _onConnectTap(BuildContext context, Server server, VpnState state) => state == VpnState.disconnected
      ? ServerConnectionActions.connect(context, server)
      : ServerConnectionActions.disconnect(context);

  Future<void> _openPicker(BuildContext context, List<Server> servers, Server current, VpnState state) async {
    final chosen = await CozyServerPicker.show(
      context,
      currentId: current.id,
      onOpenDetails: (server) => _openServerDetails(context, server),
    );
    if (chosen == null || !context.mounted) return;
    await _switchTo(context, chosen, current, state);
  }

  /// Makes [chosen] the current server; while connected, reconnects to it.
  Future<void> _switchTo(BuildContext context, Server chosen, Server current, VpnState state) async {
    if (chosen.id == current.id) return;

    if (state == VpnState.disconnected) {
      ServersScope.controllerOf(context, listen: false).pickServer(chosen.id);
    } else {
      // Switching while connected: reconnect to the chosen one.
      await ServerConnectionActions.disconnect(context);
      if (context.mounted) await ServerConnectionActions.connect(context, chosen);
    }
  }

  Future<void> _openServerDetails(BuildContext context, Server server) async {
    final controller = ServersScope.controllerOf(context, listen: false);
    await context.push(ServerDetailsPopUp(serverId: server.id));
    controller.fetchServers();
  }

  Future<void> _pushServerDetailsScreen({ServerData? preloadedData}) async {
    final controller = ServersScope.controllerOf(context, listen: false);
    await context.push(
      ScaffoldMessengerProvider(
        value: _scaffoldMessengerKey.currentState ?? ScaffoldMessenger.of(context),
        child: preloadedData != null
            ? ServerDetailsPopUp.preloaded(preloadedData: preloadedData)
            : const ServerDetailsPopUp(),
      ),
      route: AppRoutes.serverDetails,
    );
    controller.fetchServers();
  }
}

bool _isTrouble(VpnState state) => switch (state) {
  VpnState.waitingForRecovery || VpnState.recovering || VpnState.waitingForNetwork => true,
  _ => false,
};

/// The big round button: Marsik sleeps when off, fiddles with a gear while
/// connecting, holds the shield when on and worries when the link dropped.
class _ConnectButton extends StatelessWidget {
  final VpnState state;
  final VoidCallback onTap;

  /// Diameter: 224 on the phone, larger in the wide window.
  final double size;

  const _ConnectButton({required this.state, required this.onTap, this.size = 224});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final connected = state == VpnState.connected;
    final busy = state == VpnState.connecting || _isTrouble(state);
    final ringColor = _isTrouble(state) ? colors.attention : colors.accent;
    final image = switch (state) {
      VpnState.connected => AssetImages.catShield,
      VpnState.connecting => AssetImages.catGear,
      VpnState.disconnected => AssetImages.catSleeping,
      _ => AssetImages.catAlert,
    };

    return Semantics(
      button: true,
      label: connected ? context.ln.disconnect : context.ln.connect,
      child: SizedBox(
        width: size + 24,
        height: size + 24,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (busy)
              SizedBox(
                width: size + 16,
                height: size + 16,
                child: CircularProgressIndicator(strokeWidth: 5, color: ringColor),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: connected ? colors.blend : colors.backgroundAdditional,
                border: Border.all(
                  color: connected ? colors.accent : (busy ? ringColor : colors.backgroundSystem),
                  width: 4,
                ),
                boxShadow: [
                  if (connected)
                    BoxShadow(color: colors.accent.withValues(alpha: 0.35), blurRadius: 32, spreadRadius: 2),
                ],
              ),
              child: Material(
                type: MaterialType.transparency,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(36),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Image.asset(image, key: ValueKey(image)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBlock extends StatelessWidget {
  final VpnState state;
  final DateTime? connectedSince;
  final Server server;

  const _StatusBlock({required this.state, required this.connectedSince, required this.server});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = switch (state) {
      VpnState.connected => context.ln.trayStatusConnected,
      VpnState.disconnected => context.ln.trayStatusDisconnected,
      _ => context.ln.trayStatusConnecting,
    };
    final latency = ServerLatencyScope.of(context).resultFor(server.id);
    final details = <String>[
      if (state == VpnState.connected && connectedSince != null)
        context.ln.cozySessionTime(_formatDuration(DateTime.now().difference(connectedSince!))),
      if (latency?.latency != null) context.ln.cozyPing(latency!.latency!.inMilliseconds),
      if (latency != null && !latency.reachable && state != VpnState.connected) context.ln.serverUnreachable,
    ];

    final titleColor = state == VpnState.connected ? colors.accent : colors.neutralBlack;

    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: UnvalidatedVpnNotice.detected,
          builder: (context, detected, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: context.textTheme.headlineSmall?.copyWith(color: titleColor),
                ),
              ),
              // Marsik found the firmware's "no VPN" badge on this phone -
              // his note stays one tap away.
              if (detected && state == VpnState.connected)
                IconButton(
                  icon: Icon(Icons.info_outline, color: titleColor),
                  tooltip: context.ln.unvalidatedVpnTitle,
                  onPressed: () => UnvalidatedVpnNotice.show(context),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          details.isEmpty ? (state == VpnState.disconnected ? context.ln.cozyTapToConnect : '') : details.join(' · '),
          textAlign: TextAlign.center,
          style: context.textTheme.bodyMedium?.copyWith(color: colors.neutralDark),
        ),
      ],
    );
  }

  static String _formatDuration(Duration duration) {
    String two(int value) => value.toString().padLeft(2, '0');

    return '${two(duration.inHours)}:${two(duration.inMinutes % 60)}:${two(duration.inSeconds % 60)}';
  }
}

class _CurrentServerCard extends StatelessWidget {
  final Server server;
  final VoidCallback onTap;

  const _CurrentServerCard({required this.server, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Material(
      color: colors.backgroundAdditional,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.ln.cozyServer,
                      style: context.textTheme.labelMedium?.copyWith(color: colors.neutralDark),
                    ),
                    const SizedBox(height: 4),
                    Text(server.serverData.name, style: context.textTheme.titleMedium),
                    Text(
                      server.serverData.ipAddress,
                      style: context.textTheme.bodySmall?.copyWith(color: colors.neutralDark),
                    ),
                  ],
                ),
              ),
              Icon(Icons.expand_more_rounded, color: colors.neutralDark),
            ],
          ),
        ),
      ),
    );
  }
}
