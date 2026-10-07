import 'package:flutter/material.dart';

/// Every color of the app theme (AppTheme builds ThemeData from one of
/// these). [light] is the original palette; [dark] is derived from the same
/// accent #3972AA.
class ThemePalette {
  final Brightness brightness;
  final Color accent;
  final Color accentHover;
  final Color accentPressed;
  final Color accentDisabled;
  final Color accentAdditional;
  final Color blend;
  final Color blendHover;
  final Color blendPressed;
  final Color attention;
  final Color attentionHover;
  final Color attentionPressed;
  final Color attentionDisabled;
  final Color error;
  final Color errorHover;
  final Color errorPressed;
  final Color errorDisabled;
  final Color background;
  final Color backgroundHover;
  final Color backgroundPressed;
  final Color neutralBlend;
  final Color backgroundAdditional;
  final Color backgroundElevated;

  /// Snackbar background: dark in both themes (the text on it is white).
  final Color snackBarBackground;
  final Color backgroundSystem;
  final Color backgroundSystemHover;
  final Color backgroundSystemPressed;
  final Color neutralLight;
  final Color neutralLightHover;
  final Color neutralLightPressed;
  final Color neutralLightDisabled;
  final Color neutralDark;
  final Color neutralDarkHover;
  final Color neutralDarkPressed;
  final Color neutralDarkDisabled;
  final Color neutralBlack;
  final Color neutralBlackHover;
  final Color neutralBlackPressed;
  final Color neutralBlackDisabled;
  final Color specialStaticWhite;
  final Color specialStaticWhiteHover;
  final Color specialStaticWhitePressed;
  final Color specialStaticWhiteDisabled;
  final Color staticTransparent;
  final Color appSystemTitleBarBackground;
  final Color appSystemTitleBarTitle;
  final Color dumInputDecorationIdleColor;
  final Color primary1;
  final Color primary2;
  final Color primary3;
  final Color primary4;
  final Color blend1;
  final Color blend2;
  final Color blend3;
  final Color orange1;
  final Color orange2;
  final Color orange3;
  final Color orange4;
  final Color red1;
  final Color red2;
  final Color red3;
  final Color red4;
  final Color background1;
  final Color background2;
  final Color background3;
  final Color gray1;
  final Color gray2;
  final Color gray3;
  final Color gray4;
  final Color contrast1;
  final Color contrast2;
  final Color contrast3;
  final Color contrast4;
  final Color staticBlack1;
  final Color staticBlack2;
  final Color staticBlack3;
  final Color staticWhite;
  final Color purple1;
  final Color purple2;
  final Color purple3;
  final Color purple4;
  final Color accentMainDefault;

  const ThemePalette({
    required this.brightness,
    required this.accent,
    required this.accentHover,
    required this.accentPressed,
    required this.accentDisabled,
    required this.accentAdditional,
    required this.blend,
    required this.blendHover,
    required this.blendPressed,
    required this.attention,
    required this.attentionHover,
    required this.attentionPressed,
    required this.attentionDisabled,
    required this.error,
    required this.errorHover,
    required this.errorPressed,
    required this.errorDisabled,
    required this.background,
    required this.backgroundHover,
    required this.backgroundPressed,
    required this.neutralBlend,
    required this.backgroundAdditional,
    required this.backgroundElevated,
    required this.snackBarBackground,
    required this.backgroundSystem,
    required this.backgroundSystemHover,
    required this.backgroundSystemPressed,
    required this.neutralLight,
    required this.neutralLightHover,
    required this.neutralLightPressed,
    required this.neutralLightDisabled,
    required this.neutralDark,
    required this.neutralDarkHover,
    required this.neutralDarkPressed,
    required this.neutralDarkDisabled,
    required this.neutralBlack,
    required this.neutralBlackHover,
    required this.neutralBlackPressed,
    required this.neutralBlackDisabled,
    required this.specialStaticWhite,
    required this.specialStaticWhiteHover,
    required this.specialStaticWhitePressed,
    required this.specialStaticWhiteDisabled,
    required this.staticTransparent,
    required this.appSystemTitleBarBackground,
    required this.appSystemTitleBarTitle,
    required this.dumInputDecorationIdleColor,
    required this.primary1,
    required this.primary2,
    required this.primary3,
    required this.primary4,
    required this.blend1,
    required this.blend2,
    required this.blend3,
    required this.orange1,
    required this.orange2,
    required this.orange3,
    required this.orange4,
    required this.red1,
    required this.red2,
    required this.red3,
    required this.red4,
    required this.background1,
    required this.background2,
    required this.background3,
    required this.gray1,
    required this.gray2,
    required this.gray3,
    required this.gray4,
    required this.contrast1,
    required this.contrast2,
    required this.contrast3,
    required this.contrast4,
    required this.staticBlack1,
    required this.staticBlack2,
    required this.staticBlack3,
    required this.staticWhite,
    required this.purple1,
    required this.purple2,
    required this.purple3,
    required this.purple4,
    required this.accentMainDefault,
  });

  static const light = ThemePalette(
    brightness: Brightness.light,
    accent: Color(0xFF3972AA),
    accentHover: Color(0xFF336699),
    accentPressed: Color(0xFF2D5986),
    accentDisabled: Color(0x664F8AC4),
    accentAdditional: Color(0xFF4F8AC4),
    blend: Color(0x334F8AC4),
    blendHover: Color(0x4D4F8AC4),
    blendPressed: Color(0x664F8AC4),
    attention: Color(0xFFF08400),
    attentionHover: Color(0xFFE07400),
    attentionPressed: Color(0xFFC76300),
    attentionDisabled: Color(0x80FFA424),
    error: Color(0xFFF44725),
    errorHover: Color(0xFFE7320D),
    errorPressed: Color(0xFFD02C0B),
    errorDisabled: Color(0x80F56447),
    background: Color(0xFFFFFFFF),
    backgroundHover: Color(0xFFF6F7F9),
    backgroundPressed: Color(0xFFE6EAEF),
    neutralBlend: Color(0x1A30353B),
    backgroundAdditional: Color(0xFFF6F7F9),
    backgroundElevated: Color(0xFFFFFFFF),
    snackBarBackground: Color(0xFF333E4C),
    backgroundSystem: Color(0xFFE6EAEF),
    backgroundSystemHover: Color(0xFFD1D8E0),
    backgroundSystemPressed: Color(0xFFBFC8D4),
    neutralLight: Color(0xFF9AA8B8),
    neutralLightHover: Color(0xFF8997A9),
    neutralLightPressed: Color(0xFF74869C),
    neutralLightDisabled: Color(0x3330353B),
    neutralDark: Color(0xFF74869C),
    neutralDarkHover: Color(0xFF5C6E84),
    neutralDarkPressed: Color(0xFF465567),
    neutralDarkDisabled: Color(0x4D30353B),
    neutralBlack: Color(0xFF333E4C),
    neutralBlackHover: Color(0xFF242D38),
    neutralBlackPressed: Color(0xFF1A2028),
    neutralBlackDisabled: Color(0x6630353B),
    specialStaticWhite: Color(0xFFFFFFFF),
    specialStaticWhiteHover: Color(0xFFF6F7F9),
    specialStaticWhitePressed: Color(0xFFE6EAEF),
    specialStaticWhiteDisabled: Color(0x80FFFFFF),
    staticTransparent: Colors.transparent,
    appSystemTitleBarBackground: Color(0xFFFFFFFF),
    appSystemTitleBarTitle: Color(0xFF3D3D3D),
    dumInputDecorationIdleColor: Color(0xFF73859D),
    primary1: Color(0xFF67B279),
    primary2: Color(0xFF5B9F6B),
    primary3: Color(0xFF4E8C5D),
    primary4: Color(0xFFA2D0AD),
    blend1: Color(0xFFD9ECDE),
    blend2: Color(0xFFBEDFC6),
    blend3: Color(0xFFA2D0AD),
    orange1: Color(0xFFD58500),
    orange2: Color(0xFFC77901),
    orange3: Color(0xFFB76C01),
    orange4: Color(0xFFE5B460),
    red1: Color(0xFFE9653A),
    red2: Color(0xFFE75727),
    red3: Color(0xFFDC4918),
    red4: Color(0xFFEF9071),
    background1: Color(0xFFFFFFFF),
    background2: Color(0xFFF6F6F6),
    background3: Color(0xFFE4E4E4),
    gray1: Color(0xFFA4A4A4),
    gray2: Color(0xFF7F7F7F),
    gray3: Color(0xFF5B5B5B),
    gray4: Color(0xFFE4E4E4),
    contrast1: Color(0xFF3D3D3D),
    contrast2: Color(0xFF5B5B5B),
    contrast3: Color(0xFF7F7F7F),
    contrast4: Color(0xFFA4A4A4),
    staticBlack1: Color(0xFF0A0A0A),
    staticBlack2: Color(0xFF1F1F1F),
    staticBlack3: Color(0xFF3D3D3D),
    staticWhite: Color(0xFFF6F6F6),
    purple1: Color(0xFFA870B2),
    purple2: Color(0xFF9F61AA),
    purple3: Color(0xFF92549C),
    purple4: Color(0xFFC096C7),
    accentMainDefault: Color(0xFF3972AA),
  );

  /// Derived from the same accent: a deep blue-grey background, the accent a
  /// step lighter for contrast, text roles mirrored (neutralBlack = main text).
  static const dark = ThemePalette(
    brightness: Brightness.dark,
    accent: Color(0xFF5B93CC),
    accentHover: Color(0xFF6FA2D6),
    accentPressed: Color(0xFF4F86BE),
    accentDisabled: Color(0x665B93CC),
    accentAdditional: Color(0xFF7AAAD9),
    blend: Color(0x335B93CC),
    blendHover: Color(0x4D5B93CC),
    blendPressed: Color(0x665B93CC),
    attention: Color(0xFFFF9A1F),
    attentionHover: Color(0xFFFFAA42),
    attentionPressed: Color(0xFFE68400),
    attentionDisabled: Color(0x80FFA424),
    error: Color(0xFFFF6347),
    errorHover: Color(0xFFFF7A61),
    errorPressed: Color(0xFFE84E33),
    errorDisabled: Color(0x80F56447),
    background: Color(0xFF11161D),
    backgroundHover: Color(0xFF18202A),
    backgroundPressed: Color(0xFF212B37),
    neutralBlend: Color(0x1AE6EAEF),
    backgroundAdditional: Color(0xFF18202A),
    backgroundElevated: Color(0xFF1C2530),
    snackBarBackground: Color(0xFF34414F),
    backgroundSystem: Color(0xFF26313E),
    backgroundSystemHover: Color(0xFF2E3A48),
    backgroundSystemPressed: Color(0xFF374453),
    neutralLight: Color(0xFF6B7B8F),
    neutralLightHover: Color(0xFF7B8BA0),
    neutralLightPressed: Color(0xFF8C9BAE),
    neutralLightDisabled: Color(0x33E6EAEF),
    neutralDark: Color(0xFF9AA8B8),
    neutralDarkHover: Color(0xFFAEBAC7),
    neutralDarkPressed: Color(0xFFC2CCD6),
    neutralDarkDisabled: Color(0x4DE6EAEF),
    neutralBlack: Color(0xFFE6EAEF),
    neutralBlackHover: Color(0xFFF6F7F9),
    neutralBlackPressed: Color(0xFFFFFFFF),
    neutralBlackDisabled: Color(0x66E6EAEF),
    specialStaticWhite: Color(0xFFFFFFFF),
    specialStaticWhiteHover: Color(0xFFF6F7F9),
    specialStaticWhitePressed: Color(0xFFE6EAEF),
    specialStaticWhiteDisabled: Color(0x80FFFFFF),
    staticTransparent: Colors.transparent,
    appSystemTitleBarBackground: Color(0xFF11161D),
    appSystemTitleBarTitle: Color(0xFFE6EAEF),
    dumInputDecorationIdleColor: Color(0xFF8C9BAE),
    primary1: Color(0xFF67B279),
    primary2: Color(0xFF5B9F6B),
    primary3: Color(0xFF4E8C5D),
    primary4: Color(0xFFA2D0AD),
    blend1: Color(0xFF1F3A27),
    blend2: Color(0xFF2A4D33),
    blend3: Color(0xFF3A6647),
    orange1: Color(0xFFD58500),
    orange2: Color(0xFFC77901),
    orange3: Color(0xFFB76C01),
    orange4: Color(0xFFE5B460),
    red1: Color(0xFFE9653A),
    red2: Color(0xFFE75727),
    red3: Color(0xFFDC4918),
    red4: Color(0xFFEF9071),
    background1: Color(0xFF11161D),
    background2: Color(0xFF18202A),
    background3: Color(0xFF26313E),
    gray1: Color(0xFF6B7280),
    gray2: Color(0xFF8A93A0),
    gray3: Color(0xFFAAB2BD),
    gray4: Color(0xFF2E3A48),
    contrast1: Color(0xFFE6EAEF),
    contrast2: Color(0xFFC2CCD6),
    contrast3: Color(0xFF9AA8B8),
    contrast4: Color(0xFF6B7B8F),
    staticBlack1: Color(0xFF0A0A0A),
    staticBlack2: Color(0xFF1F1F1F),
    staticBlack3: Color(0xFF3D3D3D),
    staticWhite: Color(0xFFF6F6F6),
    purple1: Color(0xFFA870B2),
    purple2: Color(0xFF9F61AA),
    purple3: Color(0xFF92549C),
    purple4: Color(0xFFC096C7),
    accentMainDefault: Color(0xFF5B93CC),
  );
}
