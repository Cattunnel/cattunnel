import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/utils/deep_link_uri_normalizer.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/repository/deep_link_repository.dart';
import 'package:trusttunnel/widgets/custom_alert_dialog.dart';
import 'package:trusttunnel/widgets/inputs/custom_text_field.dart';

/// Dialog for importing a server by pasting a `tt://` link.
///
/// Pops with the parsed [ServerData] on success, or `null` if the user
/// cancels.
class ImportLinkDialog extends StatefulWidget {
  final DeepLinkRepository repository;

  const ImportLinkDialog({
    super.key,
    required this.repository,
  });

  @override
  State<ImportLinkDialog> createState() => _ImportLinkDialogState();
}

class _ImportLinkDialogState extends State<ImportLinkDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomAlertDialog(
    title: context.ln.importLinkDialogTitle,
    scrollable: true,
    content: CustomTextField(
      controller: _controller,
      hint: context.ln.importLinkHint,
      error: _error,
      autofocus: true,
    ),
    actionsBuilder: (spacing) => [
      TextButton(
        onPressed: context.pop,
        child: Text(context.ln.cancel),
      ),
      TextButton(
        onPressed: _loading ? null : () => _import(context),
        child: Text(context.ln.importHint),
      ),
    ],
  );

  Future<void> _import(BuildContext context) async {
    final normalized = DeepLinkUriNormalizer.normalize(_controller.text);

    if (normalized == null) {
      setState(() => _error = context.ln.importLinkInvalidError);

      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final server = await widget.repository.parseDataFromLink(deepLink: normalized);

      if (context.mounted) {
        context.pop(result: server);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = context.ln.importLinkInvalidError;
        });
      }
    }
  }
}
