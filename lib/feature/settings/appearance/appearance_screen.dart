import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/theme/appearance_preferences.dart';
import 'package:trusttunnel/widgets/common/custom_radio_list_tile.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';

/// Settings -> Appearance: the style («Минимализм» / «Уютный») and the
/// light/dark/system theme. Both apply at once (AppearancePreferences).
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final preferences = context.dependencyFactory.sharedPreferences;

    return ScaffoldWrapper(
      child: Scaffold(
        appBar: CustomAppBar(title: context.ln.appearance),
        body: ListenableBuilder(
          listenable: Listenable.merge([AppearancePreferences.style, AppearancePreferences.themeMode]),
          builder: (context, _) => ListView(
            children: [
              _SectionTitle(context.ln.appearanceStyle),
              for (final style in AppStyle.values)
                CustomRadioListTile<AppStyle>(
                  value: style,
                  groupValue: AppearancePreferences.style.value,
                  title: _styleName(context, style),
                  subTitle: _styleDescription(context, style),
                  onChanged: (value) => AppearancePreferences.setStyle(preferences, value ?? style),
                ),
              const Divider(),
              _SectionTitle(context.ln.appearanceTheme),
              for (final mode in ThemeMode.values)
                CustomRadioListTile<ThemeMode>(
                  value: mode,
                  groupValue: AppearancePreferences.themeMode.value,
                  title: _themeName(context, mode),
                  onChanged: (value) => AppearancePreferences.setThemeMode(preferences, value ?? mode),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _styleName(BuildContext context, AppStyle style) => switch (style) {
    AppStyle.minimal => context.ln.appearanceStyleMinimal,
    AppStyle.cozy => context.ln.appearanceStyleCozy,
  };

  static String _styleDescription(BuildContext context, AppStyle style) => switch (style) {
    AppStyle.minimal => context.ln.appearanceStyleMinimalDescription,
    AppStyle.cozy => context.ln.appearanceStyleCozyDescription,
  };

  static String _themeName(BuildContext context, ThemeMode mode) => switch (mode) {
    ThemeMode.system => context.ln.appearanceThemeSystem,
    ThemeMode.light => context.ln.appearanceThemeLight,
    ThemeMode.dark => context.ln.appearanceThemeDark,
  };
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: context.textTheme.titleSmall?.copyWith(color: context.colors.neutralDark),
    ),
  );
}
