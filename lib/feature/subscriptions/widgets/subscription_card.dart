import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trusttunnel/common/assets/asset_icons.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/data/model/subscription_poll.dart';
import 'package:trusttunnel/feature/subscriptions/widgets/subscription_poll_format.dart';
import 'package:trusttunnel/widgets/common/custom_list_tile_separated.dart';
import 'package:trusttunnel/widgets/custom_icon.dart';

class SubscriptionCard extends StatelessWidget {
  static const _okColor = Color(0xFF2E9E5B);

  final SubscriptionData subscription;
  final bool refreshing;

  /// The last poll of this subscription's mirrors, if there was one.
  final SubscriptionPoll? poll;
  final VoidCallback onRefresh;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onShowPoll;

  const SubscriptionCard({
    super.key,
    required this.subscription,
    required this.refreshing,
    required this.onRefresh,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
    required this.onShowPoll,
    this.poll,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _tile(context),
      if (_pollLine(context) case final line?) line,
    ],
  );

  Widget _tile(BuildContext context) => CustomListTileSeparated(
    title: subscription.name,
    subtitle: _subtitle(context),
    onTileTap: onEdit,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (refreshing)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          IconButton(
            icon: Icon(Icons.refresh, size: 24, color: context.colors.neutralDark),
            onPressed: onRefresh,
          ),
        PopupMenuButton(
          icon: CustomIcon(icon: AssetIcons.moreVert, size: 24, color: context.colors.neutralDark),
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              onTap: onEdit,
              child: Text(context.ln.edit, style: context.textTheme.bodyLarge),
            ),
            PopupMenuItem<String>(
              onTap: onShare,
              child: Text(context.ln.shareSubscription, style: context.textTheme.bodyLarge),
            ),
            PopupMenuItem<String>(
              onTap: onDelete,
              child: Text(
                context.ln.delete,
                style: context.textTheme.bodyLarge?.copyWith(color: context.colors.error),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  /// The line under the subscription: what the last poll did, or which
  /// mirror is being asked right now.
  Widget? _pollLine(BuildContext context) {
    final ln = context.ln;
    final poll = this.poll;

    if (poll?.currentHost case final host?) {
      return _PollLine(
        text: ln.subscriptionPollAsking(host),
        color: context.colors.neutralDark,
        leading: const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (refreshing) {
      return _PollLine(
        text: ln.subscriptionPollRefreshing,
        color: context.colors.neutralDark,
        leading: const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (poll == null || poll.attempts.isEmpty) return null;

    if (poll.succeeded) {
      final attempt = poll.lastSucceededAttempt ?? poll.attempts.last;
      final time = DateFormat('HH:mm').format(poll.finishedAt ?? poll.startedAt);

      return _PollLine(
        text: ln.subscriptionPollUpdated(
          time,
          attempt.host,
          subscriptionPollDuration(context, attempt.durationMs),
        ),
        color: _okColor,
        leading: const Icon(Icons.check_circle_rounded, size: 16, color: _okColor),
        onTap: onShowPoll,
      );
    }

    return _PollLine(
      text: ln.subscriptionPollFailed(poll.attempts.length),
      color: context.colors.error,
      leading: Icon(Icons.cancel_rounded, size: 16, color: context.colors.error),
      onTap: onShowPoll,
    );
  }

  String _subtitle(BuildContext context) {
    final lastUpdated = subscription.lastUpdatedAt;

    if (lastUpdated == null) {
      return context.ln.subscriptionNeverUpdated;
    }

    return context.ln.subscriptionLastUpdated(DateFormat('dd.MM.yyyy HH:mm').format(lastUpdated));
  }
}

class _PollLine extends StatelessWidget {
  final String text;
  final Color? color;
  final Widget leading;
  final VoidCallback? onTap;

  const _PollLine({
    required this.text,
    required this.color,
    required this.leading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: context.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_right_rounded, size: 18, color: context.colors.neutralDark),
        ],
      ),
    ),
  );
}
