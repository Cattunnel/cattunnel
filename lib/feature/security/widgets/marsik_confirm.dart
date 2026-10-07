import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/widgets/custom_alert_dialog.dart';

/// Marsik asks [steps] questions in a row (e.g. three escalating "are you
/// sure?" before weakening a protection). Resolves to true only if every
/// step was confirmed; any cancel stops right there.
Future<bool> marsikConfirmSteps(
  BuildContext context, {
  required List<String> steps,
  String? title,
  String? confirmLabel,
  bool destructive = false,
}) async {
  for (var i = 0; i < steps.length; i++) {
    if (!context.mounted) {
      return false;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => CustomAlertDialog(
        title: steps.length > 1 ? '${title == null ? '' : '$title · '}${i + 1} / ${steps.length}' : title,
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Calmer cat on the first question, alarmed from then on.
            Image.asset(i == 0 && !destructive ? AssetImages.catFace : AssetImages.catAlert, height: 96),
            const SizedBox(height: 16),
            Text(steps[i], textAlign: TextAlign.center),
          ],
        ),
        actionsBuilder: (spacing) => [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.ln.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              i == steps.length - 1 && confirmLabel != null ? confirmLabel : dialogContext.ln.marsikConfirmContinue,
              style: destructive || i == steps.length - 1 ? TextStyle(color: dialogContext.colors.error) : null,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return false;
    }
  }

  return true;
}
