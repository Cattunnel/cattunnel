import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/widgets/custom_alert_dialog.dart';

/// Marsik's note for BBK phones (vivo, OPPO, realme, OnePlus, iQOO) whose
/// firmware reports "no VPN" when Android didn't validate the VPN network
/// although the tunnel works. ConnectionWatchdog detects it and shows the
/// note once; after that an "i" next to "Connected" reopens it.
abstract final class UnvalidatedVpnNotice {
  static const _detectedKey = 'unvalidated_vpn_notice_shown';

  /// Marsik has seen it on this phone - the "i" button is shown.
  static final detected = ValueNotifier<bool>(false);

  static void load(SharedPreferences preferences) => detected.value = preferences.getBool(_detectedKey) ?? false;

  static Future<void> markDetected(SharedPreferences preferences) async {
    detected.value = true;
    await preferences.setBool(_detectedKey, true);
  }

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialogContext) => CustomAlertDialog(
      title: dialogContext.ln.unvalidatedVpnTitle,
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(AssetImages.catShield, height: 110),
          const SizedBox(height: 16),
          Text(dialogContext.ln.unvalidatedVpnBody, textAlign: TextAlign.center),
        ],
      ),
      actionsBuilder: (spacing) => [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(dialogContext.ln.gotIt),
        ),
      ],
    ),
  );
}
