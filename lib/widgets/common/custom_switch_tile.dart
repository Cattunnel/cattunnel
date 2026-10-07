import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';

class CustomSwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Optional extra button (e.g. "edit") placed right before the switch, so
  /// rows that need one still line up with every other switch.
  final Widget? action;

  const CustomSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.subtitleColor,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    // Switches are vertically centered on the whole row, like Android's own
    // settings - one consistent rule whatever the title/subtitle wrap to.
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.textTheme.bodyLarge,
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: subtitleColor,
                  ),
                ),
            ],
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 8),
          action!,
        ],
        Padding(
          padding: EdgeInsets.only(right: 16, left: action != null ? 8 : 16),
          child: Switch(
            value: value,
            onChanged: onChanged,
          ),
        ),
      ],
    ),
  );
}
