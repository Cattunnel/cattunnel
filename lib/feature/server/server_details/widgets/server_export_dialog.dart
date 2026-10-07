import 'package:adg_share/adg_share.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/widgets/custom_alert_dialog.dart';
import 'package:trusttunnel/widgets/secure_screen.dart';

class ServerExportDialog extends StatelessWidget {
  final String link;
  final ShareClient _shareClient;

  const ServerExportDialog({
    super.key,
    required this.link,
    ShareClient shareClient = const AdgShare(),
  }) : _shareClient = shareClient;

  @override
  Widget build(BuildContext context) => SecureScreen(child: _buildDialog(context));

  Widget _buildDialog(BuildContext context) => CustomAlertDialog(
    title: context.ln.exportServerDialogTitle,
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: QrImageView(
            data: link,
            size: 200,
            errorStateBuilder: (context, error) => SizedBox(
              width: 200,
              height: 200,
              child: Center(
                child: Text(
                  context.ln.qrTooLargeError,
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodySmall,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SelectableText(
          link,
          style: context.textTheme.bodySmall,
        ),
      ],
    ),
    actionsBuilder: (spacing) => [
      TextButton(
        onPressed: () => _copyLink(context),
        child: Text(context.ln.copyLink),
      ),
      TextButton(
        onPressed: () => _shareLink(context),
        child: Text(context.ln.share),
      ),
    ],
  );

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: link));

    if (!context.mounted) {
      return;
    }

    context.pop();
    context.showInfoSnackBar(message: context.ln.linkCopiedSnackbar);
  }

  Future<void> _shareLink(BuildContext context) async {
    context.pop();
    await _shareClient.share(
      ShareRequest(
        content: [
          ShareText(link),
        ],
      ),
    );
  }
}
