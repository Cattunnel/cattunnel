import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/theme/appearance_preferences.dart';
import 'package:trusttunnel/feature/settings/appearance/widgets/style_carousel.dart';
import 'package:trusttunnel/widgets/common/custom_radio_list_tile.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';

/// Settings -> Appearance: the style, picked in the same swipe carousel as
/// on first launch (applied with a button - switching the whole app on
/// every swipe would be jumpy), and the light/dark/system theme.
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();

  static String _styleName(BuildContext context, AppStyle style) => switch (style) {
    AppStyle.minimal => context.ln.appearanceStyleMinimal,
    AppStyle.cozy => context.ln.appearanceStyleCozy,
    AppStyle.y2k => context.ln.appearanceStyleY2k,
    AppStyle.aero => context.ln.appearanceStyleAero,
  };

  static String _themeName(BuildContext context, ThemeMode mode) => switch (mode) {
    ThemeMode.system => context.ln.appearanceThemeSystem,
    ThemeMode.light => context.ln.appearanceThemeLight,
    ThemeMode.dark => context.ln.appearanceThemeDark,
  };
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  /// The style in the middle of the carousel.
  late AppStyle _shown = AppearancePreferences.style.value;

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
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: StyleCarousel(
                  initial: AppearancePreferences.style.value,
                  onChanged: (style) => setState(() => _shown = style),
                ),
              ),
              Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _shown == AppearancePreferences.style.value
                      ? const SizedBox(height: 48)
                      : FilledButton(
                          key: ValueKey(_shown),
                          onPressed: () => AppearancePreferences.setStyle(preferences, _shown),
                          child: Text(context.ln.appearanceUseStyle(AppearanceScreen._styleName(context, _shown))),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(),
              _SectionTitle(context.ln.appearanceTheme),
              for (final mode in ThemeMode.values)
                CustomRadioListTile<ThemeMode>(
                  value: mode,
                  groupValue: AppearancePreferences.themeMode.value,
                  title: AppearanceScreen._themeName(context, mode),
                  onChanged: (value) => AppearancePreferences.setThemeMode(preferences, value ?? mode),
                ),
            ],
          ),
        ),
      ),
    );
  }
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
