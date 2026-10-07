import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/theme/appearance_preferences.dart';
import 'package:trusttunnel/widgets/custom_alert_dialog.dart';

/// "What's new" once per [_release]: shown after an update (and right after
/// the onboarding on a fresh install). The main-screen style pick is in it
/// until it has been answered once ([_stylePickedKey]): always on a fresh
/// install, and one last time for people updating to 1.4.4 - later
/// releases only show their news.
class WhatsNewDialog {
  static const _seenKey = 'whats_new_seen_release';
  static const _stylePickedKey = 'whats_new_style_picked';

  /// Bump together with the text when a release has news worth a dialog.
  static const _release = '1.5.0';

  const WhatsNewDialog._();

  static Future<void> maybeShow(BuildContext context) async {
    final preferences = context.dependencyFactory.sharedPreferences;
    if (preferences.getString(_seenKey) == _release || !context.mounted) return;

    final pickStyle = preferences.getBool(_stylePickedKey) != true;
    final style = await showDialog<AppStyle>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WhatsNewView(pickStyle: pickStyle),
    );
    if (pickStyle && style != null) {
      await AppearancePreferences.setStyle(preferences, style);
      await preferences.setBool(_stylePickedKey, true);
    }
    await preferences.setString(_seenKey, _release);
  }
}

class _WhatsNewView extends StatefulWidget {
  final bool pickStyle;

  const _WhatsNewView({required this.pickStyle});

  @override
  State<_WhatsNewView> createState() => _WhatsNewViewState();
}

class _WhatsNewViewState extends State<_WhatsNewView> {
  late AppStyle _style = AppearancePreferences.style.value;

  @override
  Widget build(BuildContext context) => CustomAlertDialog(
    title: context.ln.whatsNewTitle(WhatsNewDialog._release),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The style pick comes first: with a large system font the list of
        // news pushed it far below "Done", people tapped "Done" without
        // ever seeing it and stayed on whatever was preselected.
        Image.asset(AssetImages.catWave, height: 96),
        const SizedBox(height: 12),
        if (widget.pickStyle) ...[
          Text(context.ln.whatsNewPickStyle, style: context.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StyleCard(
                  title: context.ln.appearanceStyleCozy,
                  selected: _style == AppStyle.cozy,
                  preview: const _CozyPreview(),
                  onTap: () => setState(() => _style = AppStyle.cozy),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StyleCard(
                  title: context.ln.appearanceStyleMinimal,
                  selected: _style == AppStyle.minimal,
                  preview: const _MinimalPreview(),
                  onTap: () => setState(() => _style = AppStyle.minimal),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.ln.whatsNewChangeLater,
            textAlign: TextAlign.center,
            style: context.textTheme.bodySmall?.copyWith(color: context.colors.neutralDark),
          ),
        ],
        const SizedBox(height: 16),
        Text(context.ln.whatsNewBody, style: context.textTheme.bodyMedium),
      ],
    ),
    actionsBuilder: (spacing) => [
      TextButton(
        onPressed: () => Navigator.of(context).pop(_style),
        child: Text(context.ln.whatsNewDone),
      ),
    ],
  );
}

class _StyleCard extends StatelessWidget {
  final String title;
  final bool selected;
  final Widget preview;
  final VoidCallback onTap;

  const _StyleCard({required this.title, required this.selected, required this.preview, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      selected: selected,
      button: true,
      label: title,
      child: Material(
        color: selected ? colors.blend : colors.backgroundAdditional,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: selected ? colors.accent : colors.backgroundSystem, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                SizedBox(height: 110, child: preview),
                const SizedBox(height: 8),
                // Scales down rather than breaking «Минимализм» mid-word in a narrow card.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(title, style: context.textTheme.titleSmall, textAlign: TextAlign.center, maxLines: 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiny sketch of the «Уютный» main screen: the round button with Marsik
/// and a server card under it.
class _CozyPreview extends StatelessWidget {
  const _CozyPreview();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 66,
          height: 66,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.background,
            border: Border.all(color: colors.accent, width: 2),
          ),
          child: Image.asset(AssetImages.catSleeping),
        ),
        const SizedBox(height: 10),
        Container(
          height: 18,
          decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(8)),
        ),
      ],
    );
  }
}

/// Tiny sketch of the «Минимализм» main screen: a list of servers with
/// round power buttons.
class _MinimalPreview extends StatelessWidget {
  const _MinimalPreview();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(color: colors.neutralLight, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: colors.neutralLight),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
