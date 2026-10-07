import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/app_locale_preferences.dart';
import 'package:trusttunnel/common/localization/locale_type.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/security/widgets/cyber_security_screen.dart';
import 'package:trusttunnel/feature/settings/appearance/appearance_screen.dart';
import 'package:trusttunnel/feature/settings/excluded_routes/widgets/excluded_routes_screen.dart';
import 'package:trusttunnel/feature/settings/launch_and_connection/widgets/launch_and_connection_screen.dart';
import 'package:trusttunnel/feature/settings/launch_and_connection/widgets/scope/launch_and_connection_scope.dart';
import 'package:trusttunnel/feature/settings/logs/widgets/logs_screen.dart';
import 'package:trusttunnel/feature/settings/readme/readme_screen.dart';
import 'package:trusttunnel/feature/settings/settings_about/about_screen.dart';
import 'package:trusttunnel/widgets/common/custom_arrow_list_tile.dart';
import 'package:trusttunnel/widgets/common/custom_radio_list_tile.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => ScaffoldWrapper(
    child: ScaffoldMessenger(
      child: Scaffold(
        appBar: CustomAppBar(
          title: context.ln.settings,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Image.asset(AssetImages.catGear, height: 36),
            ),
          ],
        ),
        body: ListView(
          children: [
            _SettingsSection(context.ln.settingsGroupConnection),
            CustomArrowListTile(
              title: context.ln.launchAndConnection,
              onTap: () => _pushLaunchAndConnectionScreen(context),
            ),
            const Divider(),
            CustomArrowListTile(
              title: context.ln.excludedRoutes,
              onTap: () => _pushExcludedRoutesScreen(context),
            ),
            _SettingsSection(context.ln.settingsGroupLook),
            CustomArrowListTile(
              title: context.ln.appearance,
              onTap: () => context.push(const AppearanceScreen()),
            ),
            const Divider(),
            CustomArrowListTile(
              title: context.ln.language,
              onTap: () => _showLanguageDialog(context),
            ),
            _SettingsSection(context.ln.settingsGroupSecurity),
            CustomArrowListTile(
              title: context.ln.cyberSecurity,
              onTap: () => context.push(const CyberSecurityScreen()),
            ),
            _SettingsSection(context.ln.settingsGroupHelp),
            CustomArrowListTile(
              title: context.ln.readme,
              onTap: () => context.push(const ReadmeScreen()),
            ),
            const Divider(),
            CustomArrowListTile(
              title: context.ln.connectionHelp,
              onTap: () => context.push(ReadmeScreen(name: 'CONNECTION', title: context.ln.connectionHelp)),
            ),
            const Divider(),
            CustomArrowListTile(
              title: context.ln.logs,
              onTap: () => _pushLogsScreen(context),
            ),
            const Divider(),
            CustomArrowListTile(
              title: context.ln.about,
              onTap: () => _pushAboutScreen(context),
            ),
          ],
        ),
      ),
    ),
  );

  void _pushLogsScreen(BuildContext context) => context.push(
    const LogsScreen(),
  );

  void _pushLaunchAndConnectionScreen(BuildContext context) => context.push(
    const LaunchAndConnectionScope(
      child: LaunchAndConnectionScreen(),
    ),
  );

  void _pushExcludedRoutesScreen(BuildContext context) => context.push(
    const ExcludedRoutesScreen(),
  );

  void _pushAboutScreen(BuildContext context) => context.push(
    const AboutScreen(),
  );

  Future<void> _showLanguageDialog(BuildContext context) async {
    final preferences = context.dependencyFactory.sharedPreferences;

    final selected = await showDialog<LocaleType>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(dialogContext.ln.language),
        children: [
          for (final type in AppLocalePreferences.choices)
            CustomRadioListTile<LocaleType>(
              value: type,
              groupValue: AppLocalePreferences.current.value,
              title: _languageName(dialogContext, type),
              onChanged: (value) => Navigator.of(dialogContext).pop(value),
            ),
        ],
      ),
    );

    if (selected != null) {
      await AppLocalePreferences.set(preferences, selected);
    }
  }

  /// Languages are named in themselves, so they stay findable whatever the
  /// current UI language is.
  static String _languageName(BuildContext context, LocaleType type) => switch (type) {
    LocaleType.en => 'English',
    LocaleType.ru => 'Русский',
    _ => context.ln.languageSystem,
  };
}

/// Group heading in the settings list (same look as in Appearance).
class _SettingsSection extends StatelessWidget {
  final String text;

  const _SettingsSection(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text,
      style: context.textTheme.titleSmall?.copyWith(color: context.colors.neutralDark),
    ),
  );
}
