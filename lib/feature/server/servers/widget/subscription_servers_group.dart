import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/feature/server/servers/widget/servers_card.dart';
import 'package:trusttunnel/widgets/common/custom_list_tile_separated.dart';

/// Collapsible section shown on the servers screen for one subscription:
/// a header row with the subscription's name/source, its server count and
/// last-refresh time, a refresh button, and an expand/collapse chevron,
/// followed by the servers it added when expanded.
class SubscriptionServersGroup extends StatefulWidget {
  final SubscriptionData subscription;
  final List<Server> servers;
  final bool showLatencyBadge;
  final bool refreshing;
  final VoidCallback onRefresh;

  const SubscriptionServersGroup({
    super.key,
    required this.subscription,
    required this.servers,
    required this.refreshing,
    required this.onRefresh,
    this.showLatencyBadge = false,
  });

  @override
  State<SubscriptionServersGroup> createState() => _SubscriptionServersGroupState();
}

class _SubscriptionServersGroupState extends State<SubscriptionServersGroup> {
  bool _expanded = true;

  void _toggleExpanded() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      CustomListTileSeparated(
        title: widget.subscription.name,
        subtitle: context.ln.subscriptionServersCountUpdated(
          context.ln.subscriptionServersCount(widget.servers.length),
          _lastUpdatedLabel(context),
        ),
        onTileTap: _toggleExpanded,
        contentTrailing: widget.refreshing
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                icon: Icon(Icons.refresh, size: 24, color: context.colors.neutralDark),
                onPressed: widget.onRefresh,
              ),
        // A single icon-sized trailing keeps the vertical divider lined up
        // with the one-icon trailing used by ServersCard rows below.
        trailing: IconButton(
          icon: Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            color: context.colors.neutralDark,
          ),
          onPressed: _toggleExpanded,
        ),
      ),
      if (_expanded)
        for (final server in widget.servers) ...[
          const Divider(height: 1),
          ServersCard(
            server: server,
            showLatencyBadge: widget.showLatencyBadge,
          ),
        ],
    ],
  );

  String _lastUpdatedLabel(BuildContext context) {
    final lastUpdatedAt = widget.subscription.lastUpdatedAt;

    if (lastUpdatedAt == null) {
      return context.ln.subscriptionNeverUpdated;
    }

    return context.ln.subscriptionLastUpdated(DateFormat('dd.MM.yyyy HH:mm').format(lastUpdatedAt));
  }
}
