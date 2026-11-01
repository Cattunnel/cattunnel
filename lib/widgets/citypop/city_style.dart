import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trusttunnel/common/assets/font_families.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';

/// Marks a theme as the «City pop» one (`context.isCityPop`); [night] says
/// which of its two themes (light paper or night indigo) this is.
class CityPopStyle extends ThemeExtension<CityPopStyle> {
  final bool night;

  const CityPopStyle({required this.night});

  @override
  CityPopStyle copyWith({bool? night}) => CityPopStyle(night: night ?? this.night);

  @override
  CityPopStyle lerp(ThemeExtension<CityPopStyle>? other, double t) => other is CityPopStyle && t >= 0.5 ? other : this;
}

extension CityPopContext on BuildContext {
  bool get isCityPop => Theme.of(this).extension<CityPopStyle>() != null;

  bool get isCityNight => Theme.of(this).extension<CityPopStyle>()?.night ?? false;
}

/// Colors that do not depend on the theme palette: the red stamp, the cream
/// paper and the gold line the whole style repeats (two bands, never more).
abstract final class CityColors {
  static const red = Color(0xFFD2342F);
  static const cream = Color(0xFFF1E6CF);
  static const gold = Color(0xFFD9A441);
  static const ink = Color(0xFF2A1A2E);
  static const night = Color(0xFF1A1236);
  static const coral = Color(0xFFFF6B7F);
}

/// The «City pop» look on top of the ordinary theme built from
/// ThemePalette.cityPopLight / cityPopDark: see-through screens over
/// [CityBackdrop], rounded 20-28 dp surfaces with soft shadows, airbrush
/// pastel gradients, Dela Gothic One for headings and M PLUS 1p for text.
abstract final class CityPopTheme {
  static ThemeData apply(ThemeData base, {required bool night}) {
    final soft = night ? const Color(0x66000000) : const Color(0x33603050);
    final edge = BorderSide(color: night ? const Color(0x33FFFFFF) : const Color(0x66FFFFFF));
    final paper = night ? const Color(0xF21F1745) : const Color(0xF7FFF6E6);
    const display = TextStyle(fontFamily: FontFamilies.delaGothicOne, fontWeight: FontWeight.w400);

    RoundedRectangleBorder shape(double r) =>
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(r), side: edge);
    final round = WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    );

    return base.copyWith(
      extensions: [
        ...base.extensions.values,
        CityPopStyle(night: night),
      ],
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: paper,
      shadowColor: soft,
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.merge(display),
        headlineSmall: base.textTheme.headlineSmall?.merge(display),
        titleLarge: base.textTheme.titleLarge?.merge(display),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: (base.appBarTheme.titleTextStyle ?? base.textTheme.titleLarge)?.merge(display),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: night ? Brightness.light : Brightness.dark,
          statusBarBrightness: night ? Brightness.dark : Brightness.light,
          systemStatusBarContrastEnforced: false,
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: paper,
        elevation: 14,
        shadowColor: soft,
        surfaceTintColor: Colors.transparent,
        shape: shape(28),
        titleTextStyle: base.textTheme.titleLarge?.merge(display),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        elevation: 14,
        shadowColor: soft,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          side: edge,
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: night ? const Color(0xB32A1D54) : const Color(0xC7FFFAF0),
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: soft,
        shape: shape(24),
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(color: paper, shape: shape(20), shadowColor: soft),
      snackBarTheme: base.snackBarTheme.copyWith(shape: shape(20), behavior: SnackBarBehavior.floating),
      filledButtonTheme: FilledButtonThemeData(style: base.filledButtonTheme.style?.copyWith(shape: round)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: base.elevatedButtonTheme.style?.copyWith(shape: round)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: base.outlinedButtonTheme.style?.copyWith(shape: round)),
      textButtonTheme: TextButtonThemeData(style: base.textButtonTheme.style?.copyWith(shape: round)),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(shape: shape(22)),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        indicatorColor: night ? const Color(0x55FF6B7F) : const Color(0x44D2342F),
      ),
      navigationRailTheme: base.navigationRailTheme.copyWith(
        backgroundColor: Colors.transparent,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}

/// A soft airbrushed sky behind every page except the home (which draws the
/// live scene itself): pastel gradients, a glow, nothing that moves, so lists
/// and forms stay calm and cheap.
class CityBackdrop extends StatelessWidget {
  final Widget child;

  /// The home draws its own scene: only the page's content is passed through.
  final bool passThrough;

  const CityBackdrop({super.key, required this.child, this.passThrough = false});

  @override
  Widget build(BuildContext context) {
    if (passThrough) return child;

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(painter: _SkyPainter(night: context.isCityNight)),
        ),
        child,
      ],
    );
  }
}

class _SkyPainter extends CustomPainter {
  final bool night;

  const _SkyPainter({required this.night});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final sky = night
        ? const [Color(0xFF120B2E), Color(0xFF2B1650), Color(0xFF5B2A7A), Color(0xFF9A3C86)]
        : const [Color(0xFFB9B4F0), Color(0xFFF4B2CC), Color(0xFFFFD2B0), Color(0xFFFFEBCB)];
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: sky,
          stops: const [0, 0.45, 0.78, 1],
        ).createShader(rect),
    );
    // Airbrush glow where the sun would be, and a faint second one
    final sun = Offset(size.width * 0.72, size.height * 0.30);
    canvas.drawCircle(
      sun,
      math.max(size.width, size.height) * 0.42,
      Paint()
        ..shader = RadialGradient(
          colors: [(night ? const Color(0x55FF7AB8) : const Color(0x88FFF1C4)), const Color(0x00FFFFFF)],
        ).createShader(Rect.fromCircle(center: sun, radius: math.max(size.width, size.height) * 0.42)),
    );
    final low = Offset(size.width * 0.15, size.height * 0.82);
    canvas.drawCircle(
      low,
      size.width * 0.6,
      Paint()
        ..shader = RadialGradient(
          colors: [(night ? const Color(0x33FF5A8A) : const Color(0x55FFB3A0)), const Color(0x00FFFFFF)],
        ).createShader(Rect.fromCircle(center: low, radius: size.width * 0.6)),
    );
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.night != night;
}

/// A page title with a tiny Japanese subtitle above it (設定, サーバー, ...).
/// The Japanese is decoration; the real title is the localized one.
class CityAppBarTitle extends StatelessWidget {
  final String title;

  const CityAppBarTitle(this.title, {super.key});

  static String? japaneseFor(BuildContext context, String title) {
    final ln = context.ln;

    return {
      ln.settings: '設定',
      ln.servers: 'サーバー',
      ln.routing: 'ルーティング',
      ln.logs: 'ログ',
      ln.about: '情報',
      ln.appearance: '外観',
    }[title];
  }

  @override
  Widget build(BuildContext context) {
    final ja = japaneseFor(context, title);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ja != null)
          Text(
            ja,
            style: TextStyle(
              fontFamily: FontFamilies.mPlus1p,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 2,
              height: 1.2,
              color: context.colors.neutralDark,
            ),
          ),
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
