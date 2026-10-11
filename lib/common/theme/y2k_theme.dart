import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/font_families.dart';
import 'package:trusttunnel/widgets/y2k/y2k_widgets.dart';

/// The «Y2K» look on top of the ordinary theme built from ThemePalette.y2k:
/// see-through screens (each page paints Y2kBackdrop, see ScaffoldWrapper),
/// panels and buttons with cut corners, a scan-in page transition, and the
/// [Y2kStyle] marker that widgets check with `context.isY2k`.
abstract final class Y2kTheme {
  static ThemeData apply(ThemeData base) {
    final edge = BorderSide(color: Y2kColors.steel.withValues(alpha: 0.35));
    final button = WidgetStatePropertyAll<OutlinedBorder>(y2kCut(8));

    return base.copyWith(
      extensions: [...base.extensions.values, const Y2kStyle()],
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Y2kColors.navy,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: Y2kPageTransitionsBuilder(),
          TargetPlatform.iOS: Y2kPageTransitionsBuilder(),
          TargetPlatform.linux: Y2kPageTransitionsBuilder(),
          TargetPlatform.windows: Y2kPageTransitionsBuilder(),
          TargetPlatform.macOS: Y2kPageTransitionsBuilder(),
        },
      ),
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
          fontFamily: FontFamilies.unbounded,
          fontSize: 16,
          letterSpacing: 1.2,
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: const Color(0xF2071A3A),
        shape: y2kCut(16, edge),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: const Color(0xF5071A3A),
        surfaceTintColor: Colors.transparent,
        shape: const BeveledRectangleBorder(
          side: BorderSide(color: Color(0x592F8CFF)),
          borderRadius: BorderRadius.only(topLeft: Radius.circular(18)),
        ),
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        shape: y2kCut(14, const BorderSide(color: Color(0x99CFE8FF))),
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        disabledElevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(style: base.filledButtonTheme.style?.copyWith(shape: button)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: base.elevatedButtonTheme.style?.copyWith(shape: button)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: base.outlinedButtonTheme.style?.copyWith(shape: button)),
      textButtonTheme: TextButtonThemeData(style: base.textButtonTheme.style?.copyWith(shape: button)),
      snackBarTheme: base.snackBarTheme.copyWith(
        backgroundColor: const Color(0xFF0B2A5C),
        shape: y2kCut(10, edge),
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: const Color(0xF5071A3A),
        shape: y2kCut(10, edge),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: Y2kColors.navy.withValues(alpha: 0.7),
        surfaceTintColor: Colors.transparent,
        shape: y2kCut(12, edge),
      ),
      dividerTheme: base.dividerTheme.copyWith(color: Y2kColors.steel.withValues(alpha: 0.16)),
      navigationRailTheme: base.navigationRailTheme.copyWith(
        backgroundColor: Colors.transparent,
        indicatorShape: y2kCut(8),
        indicatorColor: Y2kColors.electric.withValues(alpha: 0.3),
      ),
    );
  }
}

/// A new page comes in like a monitor drawing it: a glowing scan line runs
/// down the screen, the page appears above it (with a short flicker at the
/// start) while the old one is still seen below. Going back is a plain fade.
class Y2kPageTransitionsBuilder extends PageTransitionsBuilder {
  const Y2kPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 650);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 250);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => scanIn(context, animation, child);

  /// The same scan-in for routes that are no MaterialPageRoute (the tabs).
  static Widget scanIn(BuildContext context, Animation<double> animation, Widget child) {
    if (MediaQuery.of(context).disableAnimations) return child;

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final value = animation.value;
        if (value >= 1) return child!;
        if (animation.status == AnimationStatus.reverse) return Opacity(opacity: value, child: child);

        final t = Curves.easeInOutCubic.transform(value);
        final flicker = value < 0.15 && (value * 60).floor().isEven ? 0.6 : 1.0;

        return LayoutBuilder(
          builder: (context, box) {
            final y = t * box.maxHeight;

            return Stack(
              children: [
                Opacity(
                  opacity: flicker,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const [Colors.white, Colors.white, Colors.transparent],
                      stops: [0, t, math.min(1, t + 0.015)],
                    ).createShader(bounds),
                    child: child,
                  ),
                ),
                // The beam: a soft glow trailing above a bright line.
                Positioned(
                  left: 0,
                  right: 0,
                  top: y - 46,
                  height: 48,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Y2kColors.glow.withValues(alpha: 0.22)],
                        ),
                        border: const Border(bottom: BorderSide(color: Y2kColors.ice, width: 2)),
                        boxShadow: [BoxShadow(color: Y2kColors.electric.withValues(alpha: 0.5), blurRadius: 18)],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
