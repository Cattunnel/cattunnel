import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/asset_icons.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/server_sort_option.dart';
import 'package:trusttunnel/widgets/custom_icon.dart';

/// Bottom sheet for picking [ServerSortOption]. Pops with the chosen option,
/// or `null` if dismissed without a choice.
class ServerSortSheet extends StatelessWidget {
  final ServerSortOption current;

  const ServerSortSheet({
    super.key,
    required this.current,
  });

  static Future<ServerSortOption?> show(BuildContext context, {required ServerSortOption current}) =>
      showModalBottomSheet<ServerSortOption>(
        context: context,
        showDragHandle: true,
        // Can grow (and scroll) with a large system font.
        isScrollControlled: true,
        builder: (_) => ServerSortSheet(current: current),
      );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              context.ln.sortByTitle,
              style: context.textTheme.titleMedium,
            ),
          ),
          _OptionTile(
            label: context.ln.sortByOrigin,
            selected: current == ServerSortOption.origin,
            onTap: () => Navigator.of(context).pop(ServerSortOption.origin),
          ),
          _OptionTile(
            label: context.ln.sortByName,
            selected: current == ServerSortOption.name,
            onTap: () => Navigator.of(context).pop(ServerSortOption.name),
          ),
          _OptionTile(
            label: context.ln.sortByLatency,
            selected: current == ServerSortOption.latency,
            onTap: () => Navigator.of(context).pop(ServerSortOption.latency),
          ),
        ],
      ),
    ),
  );
}

class _OptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: context.textTheme.bodyLarge),
          ),
          if (selected) CustomIcon(icon: AssetIcons.check, size: 20, color: context.colors.accent),
        ],
      ),
    ),
  );
}
