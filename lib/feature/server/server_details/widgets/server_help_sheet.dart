import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';

/// One titled paragraph of a [ServerHelpSheet]; `\n` in [body] starts a new
/// line.
typedef ServerHelpEntry = ({String title, String body});

/// The "?" help of a server form section: a bottom sheet with a few titled
/// paragraphs.
class ServerHelpSheet extends StatelessWidget {
  final String title;
  final List<ServerHelpEntry> entries;

  const ServerHelpSheet({
    super.key,
    required this.title,
    required this.entries,
  });

  static Future<void> show(BuildContext context, {required String title, required List<ServerHelpEntry> entries}) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        // Long texts and a large system font scroll.
        isScrollControlled: true,
        builder: (_) => ServerHelpSheet(title: title, entries: entries),
      );

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              Text(title, style: textTheme.titleLarge),
              for (final entry in entries)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text(entry.title, style: textTheme.titleSmall?.copyWith(color: context.colors.accent)),
                    Text(entry.body, style: textTheme.bodyMedium),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
