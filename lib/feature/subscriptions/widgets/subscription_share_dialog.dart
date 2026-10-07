import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/utils/subscription_share_link.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/widgets/custom_alert_dialog.dart';
import 'package:trusttunnel/widgets/secure_screen.dart';

/// Shows a subscription (URL + age key) as a [SubscriptionShareLink] QR code,
/// to be scanned by CatTunnel on another phone. Screenshot-protected: the
/// code is full access to the user's servers.
class SubscriptionShareDialog extends StatelessWidget {
  final SubscriptionData subscription;

  const SubscriptionShareDialog({super.key, required this.subscription});

  @override
  Widget build(BuildContext context) => SecureScreen(
    child: CustomAlertDialog(
      title: context.ln.shareSubscriptionTitle,
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: QrImageView(
                data: SubscriptionShareLink.encode(subscription),
                size: 220,
                errorStateBuilder: (context, error) => SizedBox.square(
                  dimension: 220,
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
          ),
          const SizedBox(height: 16),
          Text(
            context.ln.shareSubscriptionWarning,
            textAlign: TextAlign.center,
            style: context.textTheme.bodySmall?.copyWith(color: context.colors.error),
          ),
        ],
      ),
      actionsBuilder: (spacing) => [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.ln.gotIt),
        ),
      ],
    ),
  );
}
