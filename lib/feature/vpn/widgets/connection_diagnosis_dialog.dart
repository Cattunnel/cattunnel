import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/logging/enum/logging_level.dart';
import 'package:trusttunnel/common/logging/enum/logging_security_type.dart';
import 'package:trusttunnel/common/theme/own_style.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/vpn_configuration_log_level.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/feature/routing/routing/widgets/scope/routing_scope.dart';
import 'package:trusttunnel/feature/security/domain/security_settings.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/settings/app_logging/widgets/scope/app_logging_scope.dart';
import 'package:trusttunnel/feature/settings/excluded_routes/widgets/scope/excluded_routes_scope.dart';
import 'package:trusttunnel/feature/settings/networks/widgets/networks_screen.dart';
import 'package:trusttunnel/feature/support/problem_report.dart';
import 'package:trusttunnel/feature/vpn/domain/anti_dpi_auto.dart';
import 'package:trusttunnel/feature/vpn/domain/connection_diagnostics.dart';
import 'package:trusttunnel/feature/vpn/domain/network_fingerprint.dart';
import 'package:trusttunnel/feature/vpn/domain/network_name.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';
import 'package:trusttunnel/widgets/y2k/marsik_image.dart';

/// Marsik's "why won't it connect" report (see [ConnectionDiagnostics]):
/// a magnifier cat and a live checklist while probing, then a verdict in
/// his own words with a matching pose, plus whatever actions make sense
/// (switch to a server that works, disconnect, keep waiting).
class ConnectionDiagnosisDialog extends StatefulWidget {
  final Server server;
  final List<Server> otherServers;

  /// Test-only: show this state without running the probes. The QA
  /// screenshots need every verdict, and a real probe cannot produce all of
  /// them; the normal app passes nothing here.
  @visibleForTesting
  final ConnectionDiagnosis? debugDiagnosis;
  @visibleForTesting
  final Map<DiagnosisStep, DiagnosisStepStatus>? debugSteps;
  @visibleForTesting
  final String? debugNetworkName;
  @visibleForTesting
  final bool debugConnectedMeanwhile;
  @visibleForTesting
  final bool debugSkipDiagnostics;

  const ConnectionDiagnosisDialog({
    super.key,
    required this.server,
    required this.otherServers,
    this.debugDiagnosis,
    this.debugSteps,
    this.debugNetworkName,
    this.debugConnectedMeanwhile = false,
    this.debugSkipDiagnostics = false,
  });

  static Future<void> show(
    BuildContext context, {
    required Server server,
    required List<Server> otherServers,
  }) => showDialog<void>(
    context: context,
    barrierColor: Colors.black45,
    barrierDismissible: false,
    builder: (_) => ConnectionDiagnosisDialog(server: server, otherServers: otherServers),
  );

  @override
  State<ConnectionDiagnosisDialog> createState() => _ConnectionDiagnosisDialogState();
}

class _ConnectionDiagnosisDialogState extends State<ConnectionDiagnosisDialog> with SingleTickerProviderStateMixin {
  static const _okColor = Color(0xFF2E9E5B);

  late final AnimationController _bobController;

  final _statuses = {for (final step in DiagnosisStep.values) step: DiagnosisStepStatus.pending};
  ConnectionDiagnosis? _result;
  bool _connectedMeanwhile = false;
  Timer? _autoCloseTimer;

  /// The network name for a debug screenshot, when there is no real one.
  String? _debugNetworkName;

  bool get _debug =>
      widget.debugSkipDiagnostics ||
      widget.debugDiagnosis != null ||
      widget.debugSteps != null ||
      widget.debugNetworkName != null;

  /// The network the person is on, for the name of it.
  NetworkFingerprint? _fingerprint;

  @override
  void initState() {
    super.initState();
    _bobController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    if (_debug) {
      _statuses.addAll(
        widget.debugSteps ?? {for (final step in DiagnosisStep.values) step: DiagnosisStepStatus.skipped},
      );
      _result = widget.debugDiagnosis;
      _connectedMeanwhile = widget.debugConnectedMeanwhile;
      _debugNetworkName = widget.debugNetworkName;
    } else {
      _bobController.repeat(reverse: true);
      unawaited(_run());
      unawaited(_loadNetwork());
    }
  }

  /// The list of the networks: there the name is changed and a network can
  /// be forgotten.
  void _openNetworks() => context.push(const NetworksScreen());

  Future<void> _loadNetwork() async {
    final fingerprint = await NetworkFingerprints.current(kind: await AntiDpiAuto.networkKind());
    if (!mounted) return;
    setState(() => _fingerprint = fingerprint);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_debug) return;

    // Slow but fine after all - say so and get out of the way.
    final state = VpnScope.vpnControllerOf(context).state;
    if (state == VpnState.connected && !_connectedMeanwhile && _result?.verdict != DiagnosisVerdict.keysUpdated) {
      _connectedMeanwhile = true;
      _autoCloseTimer = Timer(const Duration(milliseconds: 2500), _close);
    }
  }

  @override
  void dispose() {
    _bobController.dispose();
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    final diagnostics = ConnectionDiagnostics(
      subscriptionRepository: context.repositoryFactory.subscriptionRepository,
      serverRepository: context.repositoryFactory.serverRepository,
      trustUserCas: SecuritySettings(context.dependencyFactory.sharedPreferences).trustUserCas,
      preferences: context.dependencyFactory.sharedPreferences,
    );

    final result = await diagnostics.run(
      widget.server,
      otherServers: widget.otherServers,
      onStep: (step, status) {
        if (mounted) {
          setState(() => _statuses[step] = status);
        }
      },
    );

    if (!mounted) {
      return;
    }

    _bobController.stop();
    setState(() => _result = result);

    final updatedServer = result.updatedServer;
    if (result.verdict == DiagnosisVerdict.keysUpdated && updatedServer != null && !_connectedMeanwhile) {
      ServersScope.controllerOf(context, listen: false).fetchServers();
      await _startVpn(updatedServer);
    }
  }

  Future<void> _startVpn(Server server) async {
    final routingProfile = RoutingScope.controllerOf(context, listen: false).routingList.firstWhereOrNull(
      (profile) => profile.id == server.serverData.routingProfileId,
    );
    if (routingProfile == null) {
      return;
    }

    final loggingController = AppLoggingScope.controllerOf(context, listen: false);
    ServersScope.controllerOf(context, listen: false).pickServer(server.id);

    // Best-effort: a failed start just leaves the VPN disconnected (the
    // user can retry from the list) instead of surfacing as an uncaught
    // error from a dialog that is already closing.
    try {
      await VpnScope.vpnControllerOf(context, listen: false).start(
        server: server,
        routingProfile: routingProfile,
        excludedRoutes: ExcludedRoutesScope.controllerOf(context, listen: false).excludedRoutes,
        logLevel: switch (loggingController.securityType) {
          LoggingSecurityType.stripped => VpnConfigurationLogLevel.error,
          LoggingSecurityType.full => switch (loggingController.loggingLevel) {
            LoggingLevel.defaultLevel => VpnConfigurationLogLevel.info,
            LoggingLevel.debug => VpnConfigurationLogLevel.debug,
          },
        },
      );
    } catch (_) {
      // See above.
    }
  }

  void _close() {
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _switchTo(Server server) async {
    final starting = _startVpn(server);
    _close();
    await starting;
  }

  Future<void> _disconnect() async {
    final stopping = VpnScope.vpnControllerOf(context, listen: false).stop();
    _close();
    await stopping;
  }

  String get _catAsset {
    if (_connectedMeanwhile) {
      return AssetImages.catShield;
    }

    final result = _result;
    if (result == null) {
      return AssetImages.catMagnifier;
    }

    if (result.alternative != null) {
      return AssetImages.catWave;
    }

    return switch (result.verdict) {
      DiagnosisVerdict.noInternet => AssetImages.catSleeping,
      DiagnosisVerdict.captivePortal => AssetImages.catSleeping,
      DiagnosisVerdict.networkCuts => AssetImages.catWires,
      DiagnosisVerdict.bypassNeeded => AssetImages.catWires,
      DiagnosisVerdict.serverTimeout ||
      DiagnosisVerdict.tlsBlocked ||
      DiagnosisVerdict.trafficBlocked => AssetImages.catWires,
      DiagnosisVerdict.serverRefused || DiagnosisVerdict.accessEnded => AssetImages.catAlert,
      DiagnosisVerdict.keysUpdated => AssetImages.catShield,
      DiagnosisVerdict.keysRejected => AssetImages.catGear,
      DiagnosisVerdict.inconclusive => AssetImages.catFace,
      DiagnosisVerdict.addressFrozen => AssetImages.catSleeping,
      DiagnosisVerdict.clockWrong => AssetImages.catAlert,
    };
  }

  String _verdictText(DiagnosisVerdict verdict) => switch (verdict) {
    DiagnosisVerdict.noInternet => context.ln.diagVerdictNoInternet,
    DiagnosisVerdict.captivePortal => context.ln.diagVerdictCaptivePortal,
    DiagnosisVerdict.networkCuts => context.ln.diagVerdictNetworkCuts,
    DiagnosisVerdict.bypassNeeded => context.ln.diagVerdictBypassNeeded,
    DiagnosisVerdict.serverTimeout => context.ln.diagVerdictServerTimeout,
    DiagnosisVerdict.serverRefused => context.ln.diagVerdictServerRefused,
    DiagnosisVerdict.tlsBlocked => context.ln.diagVerdictTlsBlocked,
    DiagnosisVerdict.trafficBlocked => context.ln.diagVerdictTrafficBlocked,
    DiagnosisVerdict.accessEnded => context.ln.diagVerdictAccessEnded,
    DiagnosisVerdict.keysUpdated => context.ln.diagVerdictKeysUpdated,
    DiagnosisVerdict.keysRejected => context.ln.diagVerdictKeysRejected,
    DiagnosisVerdict.inconclusive => context.ln.diagVerdictInconclusive,
    DiagnosisVerdict.addressFrozen => context.ln.diagVerdictAddressFrozen,
    DiagnosisVerdict.clockWrong => context.ln.diagVerdictClockWrong,
  };

  /// What the engine saw, in the person's words.
  String? _engineText(ConnectionDiagnosis? result) {
    final engine = result?.engine;
    if (engine == null) return null;
    if (engine.isHandshakeFreeze) return context.ln.diagEngineHandshakeFreeze;
    if (engine.isCut) return context.ln.diagEngineCutAfterBytes(engine.repeat);
    if (engine.isStall) return context.ln.diagEngineStall;

    return null;
  }

  /// What the anti-DPI "auto" ended with, in the person's words.
  String? _autoText(ConnectionDiagnosis? result) {
    final round = result?.auto;
    if (round == null || !round.failed) return null;
    final count = round.triedModes.length;

    return round.triedPlain ? context.ln.diagAutoFailedPlain(count) : context.ln.diagAutoFailedModes(count);
  }

  String _stepLabel(DiagnosisStep step) => switch (step) {
    DiagnosisStep.internet => context.ln.diagStepInternet,
    DiagnosisStep.server => context.ln.diagStepServer,
    DiagnosisStep.tls => context.ln.diagStepTls,
    DiagnosisStep.access => context.ln.diagStepAccess,
  };

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final done = result != null || _connectedMeanwhile;

    return Dialog(
      backgroundColor: context.hasOwnStyle ? null : context.colors.backgroundSystem,
      shape: context.hasOwnStyle ? null : RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _bobController,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, sin(_bobController.value * pi) * -6),
                child: child,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: Tween(begin: 0.85, end: 1.0).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: MarsikImage(_catAsset, key: ValueKey(_catAsset), height: 130),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              done ? context.ln.diagTitleDone : context.ln.diagTitleChecking,
              textAlign: TextAlign.center,
              style: context.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            for (final step in DiagnosisStep.values)
              _StepRow(label: _stepLabel(step), status: _statuses[step]!, okColor: _okColor),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: done
                  ? Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: _SpeechBubble(
                        text: _connectedMeanwhile ? context.ln.diagConnectedMeanwhile : _verdictText(result!.verdict),
                        extra: !_connectedMeanwhile && result?.alternative != null
                            ? context.ln.diagAlternative(result!.alternative!.serverData.name)
                            : null,
                        engine: _connectedMeanwhile ? null : _engineText(result),
                        auto: _connectedMeanwhile ? null : _autoText(result),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: 16),
            if (_fingerprint != null || _debugNetworkName != null) ...[
              _NetworkRow(
                name:
                    _debugNetworkName ??
                    networkName(context.ln, context.dependencyFactory.sharedPreferences, _fingerprint!),
                onOpen: _openNetworks,
              ),
              const SizedBox(height: 8),
            ],
            _buildActions(context, result),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, ConnectionDiagnosis? result) {
    if (_connectedMeanwhile || result?.verdict == DiagnosisVerdict.keysUpdated) {
      return TextButton(onPressed: _close, child: Text(context.ln.gotIt));
    }

    final alternative = result?.alternative;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (alternative != null) ...[
          FilledButton(
            onPressed: () => _switchTo(alternative),
            child: Text(context.ln.diagSwitchTo(alternative.serverData.name)),
          ),
          const SizedBox(height: 8),
        ],
        // Side by side where they fit, one under the other where they don't
        // (a narrow phone, a large font): never cut off.
        OverflowBar(
          alignment: MainAxisAlignment.spaceBetween,
          overflowAlignment: OverflowBarAlignment.end,
          children: [
            TextButton(onPressed: _disconnect, child: Text(context.ln.diagDisconnect)),
            TextButton(onPressed: _close, child: Text(context.ln.diagKeepWaiting)),
          ],
        ),
        TextButton(
          onPressed: () => ProblemReport.share(context, diagnosis: _result?.verdict.name),
          child: Text(context.ln.reportProblem),
        ),
      ],
    );
  }
}

/// The name of the network, and a way to open the list of the networks:
/// there the name is changed and the network can be forgotten.
class _NetworkRow extends StatelessWidget {
  final String name;
  final VoidCallback onOpen;

  const _NetworkRow({required this.name, required this.onOpen});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onOpen,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(context.ln.diagNetwork(name))),
          Icon(Icons.navigate_next, color: context.colors.neutralDark),
        ],
      ),
    ),
  );
}

class _StepRow extends StatelessWidget {
  final String label;
  final DiagnosisStepStatus status;
  final Color okColor;

  const _StepRow({required this.label, required this.status, required this.okColor});

  @override
  Widget build(BuildContext context) {
    final icon = switch (status) {
      DiagnosisStepStatus.pending => Icon(Icons.circle_outlined, size: 20, color: context.colors.neutralLight),
      DiagnosisStepStatus.running => const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      DiagnosisStepStatus.ok => Icon(Icons.check_circle_rounded, size: 20, color: okColor),
      DiagnosisStepStatus.failed => Icon(Icons.cancel_rounded, size: 20, color: context.colors.error),
      DiagnosisStepStatus.skipped => Icon(
        Icons.remove_circle_outline_rounded,
        size: 20,
        color: context.colors.neutralLightDisabled,
      ),
    };
    final dimmed = status == DiagnosisStepStatus.pending || status == DiagnosisStepStatus.skipped;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 22,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                child: KeyedSubtree(key: ValueKey(status), child: icon),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: (context.textTheme.bodyMedium ?? const TextStyle()).copyWith(
                color: dimmed ? context.colors.neutralLight : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  // Said in words, not struck through: a step that was not
                  // checked is not a step that failed. Under the label, so
                  // a narrow screen does not break the label mid-word.
                  if (status == DiagnosisStepStatus.skipped)
                    Text(
                      context.ln.diagStepNotChecked,
                      style: context.textTheme.bodySmall?.copyWith(color: context.colors.neutralLight),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Marsik "saying" the verdict: a rounded bubble with a little tail
/// pointing up at the cat.
class _SpeechBubble extends StatelessWidget {
  final String text;
  final String? extra;

  /// What the engine saw, under the verdict.
  final String? engine;

  /// What the anti-DPI "auto" tried, under the verdict.
  final String? auto;

  const _SpeechBubble({required this.text, this.extra, this.engine, this.auto});

  @override
  Widget build(BuildContext context) {
    // Opaque (pre-blended onto the dialog background) so the tail can cover
    // the bubble's top border where they meet.
    final fill = Color.alphaBlend(context.colors.accent.withValues(alpha: 0.08), context.colors.backgroundSystem);
    final border = context.colors.accent.withValues(alpha: 0.35);

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: context.textTheme.bodyMedium),
              if (engine != null) ...[
                const SizedBox(height: 8),
                Text(
                  engine!,
                  style: context.textTheme.bodySmall,
                ),
              ],
              if (auto != null) ...[
                const SizedBox(height: 8),
                Text(
                  auto!,
                  style: context.textTheme.bodySmall,
                ),
              ],
              if (extra != null) ...[
                const SizedBox(height: 8),
                Text(
                  extra!,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          top: -9,
          child: CustomPaint(
            size: const Size(18, 10),
            painter: _BubbleTailPainter(fill: fill, border: border),
          ),
        ),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color fill;
  final Color border;

  const _BubbleTailPainter({required this.fill, required this.border});

  @override
  void paint(Canvas canvas, Size size) {
    // The last pixel row overlaps the bubble's top border: the filled
    // triangle hides that bit of border, and only the two slanted edges get
    // stroked, so the tail reads as part of the bubble outline.
    final triangle = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    final edges = Path()
      ..moveTo(0, size.height - 1)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height - 1);

    canvas
      ..drawPath(triangle, Paint()..color = fill)
      ..drawPath(
        edges,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke,
      );
  }

  @override
  bool shouldRepaint(_BubbleTailPainter oldDelegate) => oldDelegate.fill != fill || oldDelegate.border != border;
}
