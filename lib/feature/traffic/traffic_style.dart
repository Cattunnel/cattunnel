import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/theme/appearance_preferences.dart';
import 'package:trusttunnel/widgets/aero/aero_widgets.dart';
import 'package:trusttunnel/widgets/y2k/y2k_widgets.dart';

/// Colors and cards of the statistics screen in the current style: the
/// series palette (one hue per server, "others" grey), the text/grid tones
/// and the card the blocks sit on (Y2K glass with cut corners, Aero glass,
/// a rounder card for «Уютный», a flat one for «Минимализм»).
class TrafficStyle {
  final List<Color> palette;
  final Color others;
  final Color text;
  final Color muted;
  final Color grid;
  final Color heat;
  final Color up;
  final Color down;
  final double radius;

  const TrafficStyle({
    required this.palette,
    required this.others,
    required this.text,
    required this.muted,
    required this.grid,
    required this.heat,
    required this.up,
    required this.down,
    required this.radius,
  });

  static TrafficStyle of(BuildContext context) {
    final colors = context.colors;
    if (context.isY2k) {
      return const TrafficStyle(
        palette: [
          Y2kColors.electric,
          Y2kColors.glow,
          Y2kColors.warn,
          Color(0xFFB18CFF),
          Color(0xFF4FE0B0),
          Y2kColors.ice,
        ],
        others: Y2kColors.dim,
        text: Y2kColors.ice,
        muted: Y2kColors.steel,
        grid: Color(0x337FB6EA),
        heat: Y2kColors.glow,
        up: Y2kColors.warn,
        down: Color(0xFF4FE0B0),
        radius: 0,
      );
    }
    if (context.isAero) {
      final night = context.isAeroNight;

      return TrafficStyle(
        palette: [
          AeroColors.sky,
          night ? AeroColors.limeNight : const Color(0xFF6FB51F),
          const Color(0xFF00B4D8),
          const Color(0xFFFFB703),
          const Color(0xFF8E7DFF),
          const Color(0xFFFF6FA5),
        ],
        others: const Color(0xFF8FA6BF),
        text: colors.neutralBlack,
        muted: colors.neutralDark,
        grid: colors.neutralDark.withValues(alpha: 0.18),
        heat: AeroColors.sky,
        up: const Color(0xFFE76F51),
        down: const Color(0xFF2A9D8F),
        radius: 22,
      );
    }
    final dark = Theme.of(context).brightness == Brightness.dark;

    return TrafficStyle(
      palette: dark
          ? const [
              Color(0xFF6EA8E8),
              Color(0xFFF2A65A),
              Color(0xFF6CCB8E),
              Color(0xFFB79CF0),
              Color(0xFF5FCFCF),
              Color(0xFFF08DB1),
            ]
          : const [
              Color(0xFF3972AA),
              Color(0xFFE07B28),
              Color(0xFF2E9E5B),
              Color(0xFF7E5BC9),
              Color(0xFF1C9C9C),
              Color(0xFFD04F82),
            ],
      others: colors.neutralDark.withValues(alpha: 0.55),
      text: colors.neutralBlack,
      muted: colors.neutralDark,
      grid: colors.neutralDark.withValues(alpha: 0.16),
      heat: colors.accent,
      up: dark ? const Color(0xFFF2A65A) : const Color(0xFFC8501E),
      down: dark ? const Color(0xFF6CCB8E) : const Color(0xFF2E9E5B),
      radius: AppearancePreferences.style.value == AppStyle.minimal ? 12 : 24,
    );
  }
}

/// A block of the statistics screen on the current style's card.
class TrafficCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const TrafficCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    if (context.isY2k) {
      return Y2kGlassCard(child: content);
    }
    if (context.isAero) {
      return AeroGlass(radius: 22, child: content);
    }
    final colors = context.colors;
    final style = TrafficStyle.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.backgroundSystem,
        borderRadius: BorderRadius.circular(style.radius),
        border: AppearancePreferences.style.value == AppStyle.minimal
            ? Border.all(color: colors.neutralDark.withValues(alpha: 0.15))
            : null,
      ),
      child: content,
    );
  }
}

/// The segmented pick (period, chart view) in the current style.
class TrafficSegments<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T> onChanged;

  const TrafficSegments({super.key, required this.items, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final style = TrafficStyle.of(context);
    final accent = style.palette.first;
    final y2k = context.isY2k;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (value, label) in items)
          ChoiceChip(
            label: Text(label),
            selected: value == selected,
            showCheckmark: false,
            onSelected: (_) => onChanged(value),
            labelStyle: TextStyle(
              color: value == selected ? (y2k ? Y2kColors.ink : Colors.white) : style.text,
              fontWeight: value == selected ? FontWeight.w600 : FontWeight.w400,
            ),
            selectedColor: y2k ? Y2kColors.glow : accent,
            backgroundColor: y2k ? Y2kColors.navy.withValues(alpha: 0.6) : style.grid.withValues(alpha: 0.35),
            side: BorderSide(color: y2k ? Y2kColors.steel.withValues(alpha: 0.4) : Colors.transparent),
            shape: y2k
                ? const BeveledRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(6)))
                : const StadiumBorder(),
          ),
      ],
    );
  }
}
