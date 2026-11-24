import 'package:flutter/material.dart';
import 'package:trusttunnel/common/localization/localization.dart';

/// Asks for the user's own name of a group. Pops with the text (empty means
/// "back to the original name") or null when cancelled.
class GroupRenameDialog extends StatefulWidget {
  final String initial;

  const GroupRenameDialog({super.key, required this.initial});

  static Future<String?> show(BuildContext context, {required String initial}) => showDialog<String>(
    context: context,
    builder: (_) => GroupRenameDialog(initial: initial),
  );

  @override
  State<GroupRenameDialog> createState() => _GroupRenameDialogState();
}

class _GroupRenameDialogState extends State<GroupRenameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.ln.groupRenameTitle),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 40,
      decoration: InputDecoration(hintText: context.ln.groupRenameHint),
      onSubmitted: (value) => Navigator.of(context).pop(value),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.ln.cancel)),
      TextButton(onPressed: () => Navigator.of(context).pop(_controller.text), child: Text(context.ln.save)),
    ],
  );
}
