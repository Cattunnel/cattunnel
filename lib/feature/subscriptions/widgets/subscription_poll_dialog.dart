import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/subscription_poll.dart';
import 'package:trusttunnel/feature/subscriptions/widgets/subscription_poll_format.dart';
import 'package:trusttunnel/widgets/custom_alert_dialog.dart';

/// The attempts of the last subscription poll, in order, with what each
/// mirror answered. Shown from the status line under the subscription.
class SubscriptionPollDialog extends StatelessWidget {
  static const _okColor = Color(0xFF2E9E5B);

  final SubscriptionPoll poll;

  const SubscriptionPollDialog({super.key, required this.poll});

  @override
  Widget build(BuildContext context) => CustomAlertDialog(
    title: context.ln.subscriptionPollDialogTitle,
    scrollable: true,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.ln.subscriptionPollDialogDescription,
          style: context.textTheme.bodySmall?.copyWith(color: context.colors.neutralDark),
        ),
        const SizedBox(height: 16),
        for (final attempt in poll.attempts) _AttemptRow(attempt: attempt, okColor: _okColor),
      ],
    ),
    actionsBuilder: (spacing) => [
      TextButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: Text(context.ln.subscriptionPollClose),
      ),
    ],
  );
}

class _AttemptRow extends StatelessWidget {
  final SubscriptionPollAttempt attempt;
  final Color okColor;

  const _AttemptRow({required this.attempt, required this.okColor});

  @override
  Widget build(BuildContext context) {
    final ok = attempt.succeeded;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 20,
            color: ok ? okColor : context.colors.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(attempt.host, style: context.textTheme.bodyLarge),
                Text(
                  '${subscriptionPollOutcomeLabel(context, attempt)} · '
                  '${subscriptionPollDuration(context, attempt.durationMs)}',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: ok ? okColor : context.colors.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
