import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/logging/enum/logging_level.dart';
import 'package:trusttunnel/common/logging/enum/logging_security_type.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/vpn_configuration_log_level.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/feature/routing/routing/widgets/scope/routing_scope.dart';
import 'package:trusttunnel/feature/security/domain/security_settings.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/settings/app_logging/widgets/scope/app_logging_scope.dart';
import 'package:trusttunnel/feature/settings/excluded_routes/widgets/scope/excluded_routes_scope.dart';
import 'package:trusttunnel/feature/support/problem_report.dart';
import 'package:trusttunnel/feature/vpn/domain/connection_diagnostics.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';

/// Marsik's "why won't it connect" report (see [ConnectionDiagnostics]):
/// a magnifier cat and a live checklist while probing, then a verdict in
/// his own words with a matching pose, plus whatever actions make sense
/// (switch to a server that works, disconnect, keep waiting).
class ConnectionDiagnosisDialog extends StatefulWidget {
  final Server server;
  final List<Server> otherServers;

  const ConnectionDiagnosisDialog({
    super.key,
    required this.server,
    required this.otherServers,
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

  @override
  void initState() {
    super.initState();
    _bobController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    unawaited(_run());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

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
      DiagnosisVerdict.serverTimeout ||
      DiagnosisVerdict.tlsBlocked ||
      DiagnosisVerdict.trafficBlocked => AssetImages.catWires,
      DiagnosisVerdict.serverRefused || DiagnosisVerdict.accessEnded => AssetImages.catAlert,
      DiagnosisVerdict.sniBlocked => AssetImages.catMagnifier,
      DiagnosisVerdict.keysUpdated => AssetImages.catShield,
      DiagnosisVerdict.keysRejected => AssetImages.catGear,
      DiagnosisVerdict.inconclusive => AssetImages.catFace,
      DiagnosisVerdict.addressFrozen => AssetImages.catSleeping,
    };
  }

  String _verdictText(DiagnosisVerdict verdict) => switch (verdict) {
    DiagnosisVerdict.noInternet => context.ln.diagVerdictNoInternet,
    DiagnosisVerdict.serverTimeout => context.ln.diagVerdictServerTimeout,
    DiagnosisVerdict.serverRefused => context.ln.diagVerdictServerRefused,
    DiagnosisVerdict.sniBlocked => context.ln.diagVerdictSniBlocked,
    DiagnosisVerdict.tlsBlocked => context.ln.diagVerdictTlsBlocked,
    DiagnosisVerdict.trafficBlocked => context.ln.diagVerdictTrafficBlocked,
    DiagnosisVerdict.accessEnded => context.ln.diagVerdictAccessEnded,
    DiagnosisVerdict.keysUpdated => context.ln.diagVerdictKeysUpdated,
    DiagnosisVerdict.keysRejected => context.ln.diagVerdictKeysRejected,
    DiagnosisVerdict.inconclusive => context.ln.diagVerdictInconclusive,
    DiagnosisVerdict.addressFrozen => context.ln.diagVerdictAddressFrozen,
  };

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
      backgroundColor: context.colors.backgroundSystem,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
                child: Image.asset(_catAsset, key: ValueKey(_catAsset), height: 130),
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
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: 16),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                decoration: status == DiagnosisStepStatus.skipped ? TextDecoration.lineThrough : null,
              ),
              child: Text(label),
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

  const _SpeechBubble({required this.text, this.extra});

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
