import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/settings/app_split/widgets/app_split_screen.dart';
import 'package:trusttunnel/feature/settings/ru_services/widgets/ru_services_rules_screen.dart';
import 'package:trusttunnel/widgets/custom_alert_dialog.dart';

/// "Split" in the Routing tab: what goes around the VPN - sites and IPs
/// (the direct list, same one as "Russian services" in Settings) or apps
/// (Android only).
Future<void> showSplitChoiceDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (dialogContext) => CustomAlertDialog(
    scrollable: true,
    title: context.ln.splitTitle,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SplitChoice(
          icon: Icons.language,
          title: context.ln.splitSitesTitle,
          subtitle: context.ln.splitSitesDescription,
          onTap: () {
            Navigator.of(dialogContext).pop();
            context.push(const RuServicesRulesScreen());
          },
        ),
        if (defaultTargetPlatform == TargetPlatform.android)
          _SplitChoice(
            icon: Icons.apps,
            title: context.ln.appSplitTitle,
            subtitle: context.ln.appSplitEntryDescription,
            onTap: () {
              Navigator.of(dialogContext).pop();
              context.push(const AppSplitScreen());
            },
          ),
      ],
    ),
  ),
);

class _SplitChoice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SplitChoice({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: context.colors.neutralDark),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: Icon(Icons.chevron_right, color: context.colors.neutralDark),
    onTap: onTap,
  );
}
