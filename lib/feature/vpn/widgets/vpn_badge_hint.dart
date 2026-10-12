import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/widgets/aero/aero_widgets.dart';
import 'package:trusttunnel/widgets/y2k/marsik_image.dart';
import 'package:trusttunnel/widgets/y2k/y2k_widgets.dart';

/// Marsik's word about the firmware's "no internet" badge. Many Android
/// phones mark the VPN network with "!" / "No internet" when Android didn't
/// validate it (e.g. with the Russian networks' ~2200 routes) although the
/// tunnel works. ConnectionWatchdog asks Android once per connection and sets
/// [unvalidated]; the home screen then shows [VpnBadgeHint]: a speech bubble
/// the first time, a small chip after "Got it" (tap - the bubble again).
abstract final class VpnBadgeHintState {
  static const _dismissedKey = 'vpn_badge_hint_dismissed';

  /// Android reported this connection's VPN network as not validated.
  /// Cleared when the VPN leaves "connected".
  static final unvalidated = ValueNotifier<bool>(false);

  /// The bubble is open (until the first "Got it", then only on a chip tap).
  static final expanded = ValueNotifier<bool>(true);

  static SharedPreferences? _preferences;

  static void load(SharedPreferences preferences) {
    _preferences = preferences;
    expanded.value = !(preferences.getBool(_dismissedKey) ?? false);
  }

  static Future<void> dismiss() async {
    expanded.value = false;
    await _preferences?.setBool(_dismissedKey, true);
  }
}

/// The bubble/chip itself, in the current style. Takes no room unless
/// [VpnBadgeHintState.unvalidated] is set.
class VpnBadgeHint extends StatelessWidget {
  final EdgeInsetsGeometry padding;

  const VpnBadgeHint({super.key, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: VpnBadgeHintState.unvalidated,
    builder: (context, unvalidated, _) => ValueListenableBuilder<bool>(
      valueListenable: VpnBadgeHintState.expanded,
      builder: (context, expanded, _) => AnimatedSize(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(animation), child: child),
          ),
          child: !unvalidated
              ? const SizedBox(width: double.infinity)
              : Padding(
                  key: ValueKey(expanded),
                  padding: padding,
                  child: expanded ? const _Bubble() : const Center(child: _Chip()),
                ),
        ),
      ),
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble();

  @override
  Widget build(BuildContext context) {
    final y2k = context.isY2k;
    final textColor = y2k ? Y2kColors.ice : (context.isAero ? AeroColors.ink : context.colors.neutralBlack);

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MarsikImage(AssetImages.catWave, height: 64),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.ln.vpnBadgeHintBody,
                  style: context.textTheme.bodyMedium?.copyWith(color: textColor, height: 1.35),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: VpnBadgeHintState.dismiss,
                    style: y2k ? TextButton.styleFrom(foregroundColor: Y2kColors.glow) : null,
                    child: Text(context.ln.gotIt),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (y2k) return Y2kGlassCard(child: content);
    if (context.isAero) return AeroGlass(radius: 22, child: content);

    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.backgroundSystem,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.accent.withValues(alpha: 0.35)),
      ),
      child: content,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip();

  @override
  Widget build(BuildContext context) {
    final y2k = context.isY2k;
    final aero = context.isAero;
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const MarsikImage(AssetImages.catFace, height: 22),
        const SizedBox(width: 6),
        Flexible(
          child: y2k
              ? Y2kMicro(context.ln.vpnBadgeHintChip, color: Y2kColors.glow)
              : Text(
                  context.ln.vpnBadgeHintChip,
                  style: context.textTheme.labelLarge?.copyWith(color: aero ? AeroColors.ink : context.colors.accent),
                ),
        ),
      ],
    );
    void open() => VpnBadgeHintState.expanded.value = true;
    const padding = EdgeInsets.symmetric(horizontal: 12, vertical: 6);

    if (y2k)
      return Y2kGlassCard(
        onTap: open,
        child: Padding(padding: padding, child: label),
      );
    if (aero) return AeroGlass(radius: 18, padding: padding, onTap: open, child: label);

    return Material(
      color: context.colors.backgroundSystem,
      shape: StadiumBorder(side: BorderSide(color: context.colors.accent.withValues(alpha: 0.35))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: open,
        child: Padding(padding: padding, child: label),
      ),
    );
  }
}
