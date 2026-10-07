import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/feature/security/domain/security_platform.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/support/problem_report.dart';
import 'package:trusttunnel/feature/vpn/widgets/connection_diagnosis_dialog.dart';
import 'package:trusttunnel/feature/vpn/widgets/unvalidated_vpn_notice.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';
import 'package:trusttunnel/widgets/custom_alert_dialog.dart';

/// Opens [ConnectionDiagnosisDialog] when a connection attempt has been
/// stuck for [_stuckAfter] - i.e. the VPN left `connected`/`disconnected`
/// and hasn't reached `connected` since. At most once per attempt; the
/// attempt itself keeps running underneath.
///
/// Must sit below the root `Navigator` (it shows a dialog).
class ConnectionWatchdog extends StatefulWidget {
  final Widget child;

  const ConnectionWatchdog({super.key, required this.child});

  @override
  State<ConnectionWatchdog> createState() => _ConnectionWatchdogState();
}

class _ConnectionWatchdogState extends State<ConnectionWatchdog> {
  static const _stuckAfter = Duration(seconds: 10);

  /// Android validates a new network within a few seconds.
  static const _validationCheckAfter = Duration(seconds: 20);

  VpnState? _state;
  Timer? _timer;
  Timer? _validationTimer;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    VpnScope.startDidNotBegin.addListener(_onStartDidNotBegin);
    VpnScope.antiDpiAutoFailed.addListener(_onAntiDpiAutoFailed);
    UnvalidatedVpnNotice.load(context.dependencyFactory.sharedPreferences);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onState(VpnScope.vpnControllerOf(context).state);
  }

  /// The VPN didn't even begin connecting (see VpnScope._watchStartBegins) -
  /// Marsik says so, names the usual culprits and offers a problem report
  /// (it carries the engine log with the real reason).
  Future<void> _onStartDidNotBegin() async {
    if (!VpnScope.startDidNotBegin.value || _dialogOpen || !mounted) {
      return;
    }
    VpnScope.startDidNotBegin.value = false;

    _dialogOpen = true;
    try {
      final report = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => CustomAlertDialog(
          title: dialogContext.ln.startFailedAlertTitle,
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(AssetImages.catWires, height: 110),
              const SizedBox(height: 16),
              Text(dialogContext.ln.startFailedAlertBody, textAlign: TextAlign.center),
            ],
          ),
          actionsBuilder: (spacing) => [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogContext.ln.startFailedAlertLater),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(dialogContext.ln.startFailedAlertReport),
            ),
          ],
        ),
      );
      if (report == true && mounted) {
        await ProblemReport.share(context, diagnosis: 'startDidNotBegin');
      }
    } finally {
      _dialogOpen = false;
    }
  }

  /// Anti-DPI "auto" tried every technique and none connected (see
  /// VpnScope._startAntiDpiAuto) - Marsik says so and offers a report.
  Future<void> _onAntiDpiAutoFailed() async {
    if (!VpnScope.antiDpiAutoFailed.value || _dialogOpen || !mounted) {
      return;
    }
    VpnScope.antiDpiAutoFailed.value = false;

    _dialogOpen = true;
    try {
      final report = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => CustomAlertDialog(
          title: dialogContext.ln.antiDpiAutoFailedTitle,
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(AssetImages.catWires, height: 110),
              const SizedBox(height: 16),
              Text(dialogContext.ln.antiDpiAutoFailedBody, textAlign: TextAlign.center),
            ],
          ),
          actionsBuilder: (spacing) => [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogContext.ln.startFailedAlertLater),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(dialogContext.ln.startFailedAlertReport),
            ),
          ],
        ),
      );
      if (report == true && mounted) {
        await ProblemReport.share(context, diagnosis: 'antiDpiAutoFailed');
      }
    } finally {
      _dialogOpen = false;
    }
  }

  @override
  void dispose() {
    VpnScope.startDidNotBegin.removeListener(_onStartDidNotBegin);
    VpnScope.antiDpiAutoFailed.removeListener(_onAntiDpiAutoFailed);
    _timer?.cancel();
    _validationTimer?.cancel();
    super.dispose();
  }

  void _onState(VpnState state) {
    if (state == _state) {
      return;
    }
    _state = state;

    _validationTimer?.cancel();
    _validationTimer = state == VpnState.connected ? Timer(_validationCheckAfter, _checkValidation) : null;

    if (state == VpnState.connected || state == VpnState.disconnected) {
      _timer?.cancel();
      _timer = null;

      return;
    }

    // Any in-between state (connecting, recovering, waiting...) - start
    // counting from the first one of this attempt, not from each change.
    _timer ??= Timer(_stuckAfter, _onStuck);
  }

  Future<void> _onStuck() async {
    _timer = null;
    final state = _state;
    if (!mounted || _dialogOpen || state == VpnState.connected || state == VpnState.disconnected) {
      return;
    }

    final serversController = ServersScope.controllerOf(context, listen: false);
    final server = serversController.selectedServer;
    if (server == null) {
      return;
    }

    _dialogOpen = true;
    try {
      await ConnectionDiagnosisDialog.show(
        context,
        server: server,
        otherServers: serversController.servers.where((other) => other.id != server.id).toList(),
      );
    } finally {
      _dialogOpen = false;
    }
  }

  /// BBK firmwares (vivo, OPPO, realme, OnePlus, iQOO) report "no VPN" when
  /// Android didn't validate the VPN network - e.g. with the Russian
  /// networks' ~2200 routes - although the tunnel works. On those phones,
  /// once, Marsik says it's fine (UnvalidatedVpnNotice; later the "i" next to
  /// "Connected" reopens it). Other firmwares don't show such a badge, so
  /// nothing there.
  Future<void> _checkValidation() async {
    _validationTimer = null;
    final preferences = context.dependencyFactory.sharedPreferences;
    if (!mounted || _dialogOpen || _state != VpnState.connected || UnvalidatedVpnNotice.detected.value) {
      return;
    }

    final report = await SecurityPlatform.vpnNetworkReport();
    if (report == null || !report.isBbk || report.vpnValidated != false) {
      return;
    }
    if (!mounted || _dialogOpen || _state != VpnState.connected) {
      return;
    }

    await UnvalidatedVpnNotice.markDetected(preferences);
    if (!mounted) {
      return;
    }

    _dialogOpen = true;
    try {
      await UnvalidatedVpnNotice.show(context);
    } finally {
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
