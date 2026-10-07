import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/widgets/custom_alert_dialog.dart';

/// Shown when a VPN connection attempt fails.
class ConnectionErrorDialog extends StatelessWidget {
  final String message;

  const ConnectionErrorDialog({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => CustomAlertDialog(
    title: context.ln.connectionErrorDialogTitle,
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(AssetImages.catAlert, height: 96),
        const SizedBox(height: 16),
        Text(message),
      ],
    ),
    actionsBuilder: (spacing) => [
      TextButton(
        onPressed: context.pop,
        child: Text(context.ln.gotIt),
      ),
    ],
  );
}
