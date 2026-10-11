import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trusttunnel/common/assets/font_families.dart';
import 'package:trusttunnel/widgets/aero/aero_widgets.dart';

/// The «Аэро» look (Frutiger Aero) on top of the ordinary theme built from
/// ThemePalette.aeroLight (morning, day, evening) or aeroDark (night):
/// see-through screens over AeroBackdrop (ScaffoldWrapper), frosted rounded
/// glass for dialogs, sheets and menus, pill buttons, a bubble page
/// transition and the [AeroStyle] marker (`context.isAero`).
abstract final class AeroTheme {
  static ThemeData apply(ThemeData base, {required bool night}) {
    final edge = BorderSide(color: night ? const Color(0x738CD2FF) : const Color(0xE6FFFFFF));
    const pill = WidgetStatePropertyAll<OutlinedBorder>(StadiumBorder());
    final glass = night ? const Color(0xF20A2147) : const Color(0xF2F4FBFF);

    return base.copyWith(
      extensions: [
        ...base.extensions.values,
        AeroStyle(night: night),
      ],
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: glass,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AeroPageTransitionsBuilder(),
          TargetPlatform.iOS: AeroPageTransitionsBuilder(),
          TargetPlatform.linux: AeroPageTransitionsBuilder(),
          TargetPlatform.windows: AeroPageTransitionsBuilder(),
          TargetPlatform.macOS: AeroPageTransitionsBuilder(),
        },
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        // The sky behind the status bar is dark blue at every time of day.
        // The landscape also runs under the system's buttons: no scrim.
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarContrastEnforced: false,
        ),
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
          fontFamily: FontFamilies.nunito,
          fontWeight: FontWeight.w900,
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: glass,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30), side: edge),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: glass,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          side: edge,
        ),
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        shape: StadiumBorder(side: edge),
      ),
      filledButtonTheme: FilledButtonThemeData(style: base.filledButtonTheme.style?.copyWith(shape: pill)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: base.elevatedButtonTheme.style?.copyWith(shape: pill)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: base.outlinedButtonTheme.style?.copyWith(shape: pill)),
      textButtonTheme: TextButtonThemeData(style: base.textButtonTheme.style?.copyWith(shape: pill)),
      snackBarTheme: base.snackBarTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: edge),
        behavior: SnackBarBehavior.floating,
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: glass,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: edge),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: night ? const Color(0x8C0E2C5A) : const Color(0x99FFFFFF),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: edge),
      ),
      navigationRailTheme: base.navigationRailTheme.copyWith(
        backgroundColor: Colors.transparent,
        indicatorShape: const StadiumBorder(),
        indicatorColor: AeroColors.sky.withValues(alpha: 0.35),
      ),
    );
  }
}

/// A new page surfaces like a bubble: it fades in while growing from 94 %
/// and rising a little, with an easing that settles softly. Cheap on
/// purpose (no clipping or blur), so it stays smooth over the live
/// backdrop. Going back is a plain fade.
class AeroPageTransitionsBuilder extends PageTransitionsBuilder {
  const AeroPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 420);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => bubbleIn(context, animation, child);

  /// The same for routes that are no MaterialPageRoute (the tabs).
  static Widget bubbleIn(BuildContext context, Animation<double> animation, Widget child) {
    if (MediaQuery.of(context).disableAnimations) return child;

    final fade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.7, curve: Curves.easeOut),
    );
    final grow = CurvedAnimation(parent: animation, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);

    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(grow),
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(grow),
          child: child,
        ),
      ),
    );
  }
}
