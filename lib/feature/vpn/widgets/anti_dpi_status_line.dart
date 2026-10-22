import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';

/// What the anti-DPI "auto" is doing, right under the connect button.
///
/// The automation tries several handshakes in a row, and without a word the
/// person sees only a spinner for a minute. The words are plain on purpose:
/// no TTL, no SNI, no mode numbers - "the filter cuts the connection",
/// "I remembered: this network needs the bypass".
class AntiDpiStatusLine extends StatelessWidget {
  const AntiDpiStatusLine({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AntiDpiStatus?>(
    valueListenable: VpnScope.antiDpiStatus,
    builder: (context, status, _) => AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: status == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _text(context, status),
                textAlign: TextAlign.center,
                style: context.textTheme.bodySmall?.copyWith(color: context.colors.neutralDark),
              ),
            ),
    ),
  );

  String _text(BuildContext context, AntiDpiStatus status) => switch (status.step) {
    AntiDpiStep.tryingDirect => context.ln.antiDpiStatusDirect,
    AntiDpiStep.cut => context.ln.antiDpiStatusCut,
    AntiDpiStep.tryingTechnique =>
      status.total == 1
          ? context.ln.antiDpiStatusTechniqueSingle
          : context.ln.antiDpiStatusTechnique(status.index, status.total),
    AntiDpiStep.worked =>
      status.plainWorked
          ? context.ln.antiDpiStatusWorkedPlain(status.networkName)
          : context.ln.antiDpiStatusWorkedBypass(status.networkName),
    AntiDpiStep.failed =>
      status.triedPlain
          ? context.ln.antiDpiStatusFailedPlain(status.bypassTried)
          : context.ln.antiDpiStatusFailedModes(status.bypassTried),
  };
}
