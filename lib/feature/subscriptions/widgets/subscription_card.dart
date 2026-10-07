import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trusttunnel/common/assets/asset_icons.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/widgets/common/custom_list_tile_separated.dart';
import 'package:trusttunnel/widgets/custom_icon.dart';

class SubscriptionCard extends StatelessWidget {
  final SubscriptionData subscription;
  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const SubscriptionCard({
    super.key,
    required this.subscription,
    required this.refreshing,
    required this.onRefresh,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => CustomListTileSeparated(
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

  String _subtitle(BuildContext context) {
    final lastUpdated = subscription.lastUpdatedAt;

    if (lastUpdated == null) {
      return context.ln.subscriptionNeverUpdated;
    }

    return context.ln.subscriptionLastUpdated(DateFormat('dd.MM.yyyy HH:mm').format(lastUpdated));
  }
}
