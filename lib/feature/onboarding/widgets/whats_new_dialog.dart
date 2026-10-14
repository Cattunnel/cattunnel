import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/theme/appearance_preferences.dart';
import 'package:trusttunnel/feature/settings/appearance/widgets/style_carousel.dart';
import 'package:trusttunnel/widgets/custom_alert_dialog.dart';
import 'package:trusttunnel/widgets/y2k/marsik_image.dart';

/// "What's new" once per [_release]: shown after an update (and right after
/// the onboarding on a fresh install). The main-screen style pick is in it
/// until it has been answered once ([_stylePickedKey]): always on a fresh
/// install, and once more in 1.5.3, which brought two new styles (Y2K and
/// Aero) - the current style stays picked, so "Done" changes nothing.
class WhatsNewDialog {
  static const _seenKey = 'whats_new_seen_release';
  static const _stylePickedKey = 'whats_new_style_picked_153';

  /// Bump together with the text when a release has news worth a dialog.
  static const _release = '1.5.5';

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
        const MarsikImage(AssetImages.catWave, height: 96),
        const SizedBox(height: 12),
        if (widget.pickStyle) ...[
          Text(context.ln.whatsNewPickStyle, style: context.textTheme.titleSmall),
          const SizedBox(height: 8),
          StyleCarousel(
            initial: _style,
            onChanged: (style) => setState(() => _style = style),
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
