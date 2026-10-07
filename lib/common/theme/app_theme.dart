import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trusttunnel/common/assets/asset_icons.dart';
import 'package:trusttunnel/common/assets/font_families.dart';
import 'package:trusttunnel/common/extensions/theme_extensions.dart';
import 'package:trusttunnel/common/theme/theme_palette.dart';
import 'package:trusttunnel/widgets/custom_icon.dart';

class AppTheme {
  final ThemePalette _p;

  AppTheme(this._p);

  // Legacy colors

  // New colors (Colors and styles Library)

  late final _customColors = CustomColors(
    accent: _p.accent,
    accentHover: _p.accentHover,
    accentPressed: _p.accentPressed,
    accentDisabled: _p.accentDisabled,
    blend: _p.blend,
    blendHover: _p.blendHover,
    blendPressed: _p.blendPressed,
    attention: _p.attention,
    attentionHover: _p.attentionHover,
    attentionPressed: _p.attentionPressed,
    attentionDisabled: _p.attentionDisabled,
    error: _p.error,
    errorHover: _p.errorHover,
    errorPressed: _p.errorPressed,
    errorDisabled: _p.errorDisabled,
    background: _p.background,
    backgroundAdditional: _p.backgroundAdditional,
    backgroundElevated: _p.backgroundElevated,
    backgroundSystem: _p.backgroundSystem,
    backgroundSystemHover: _p.backgroundSystemHover,
    backgroundSystemPressed: _p.backgroundSystemPressed,
    neutralLight: _p.neutralLight,
    neutralLightHover: _p.neutralLightHover,
    neutralLightPressed: _p.neutralLightPressed,
    neutralLightDisabled: _p.neutralLightDisabled,
    neutralBlack: _p.neutralBlack,
    neutralBlackHover: _p.neutralBlackHover,
    neutralBlackPressed: _p.neutralBlackPressed,
    neutralBlackDisabled: _p.neutralBlackDisabled,
    neutralDark: _p.neutralDark,
    neutralDarkHover: _p.neutralDarkHover,
    neutralDarkPressed: _p.neutralDarkPressed,
    neutralDarkDisabled: _p.neutralDarkDisabled,
    specialStaticWhite: _p.specialStaticWhite,
    specialStaticWhiteHover: _p.specialStaticWhiteHover,
    specialStaticWhitePressed: _p.specialStaticWhitePressed,
    specialStaticWhiteDisabled: _p.specialStaticWhiteDisabled,
    staticTransparent: _p.staticTransparent,
    appSystemTitleBarBackground: _p.appSystemTitleBarBackground,
    appSystemTitleBarTitle: _p.appSystemTitleBarTitle,
    primary1: _p.primary1,
    primary2: _p.primary2,
    primary3: _p.primary3,
    primary4: _p.primary4,
    blend1: _p.blend1,
    blend2: _p.blend2,
    blend3: _p.blend3,
    orange1: _p.orange1,
    orange2: _p.orange2,
    orange3: _p.orange3,
    orange4: _p.orange4,
    red1: _p.red1,
    red2: _p.red2,
    red3: _p.red3,
    red4: _p.red4,
    background1: _p.background1,
    background2: _p.background2,
    background3: _p.background3,
    gray1: _p.gray1,
    gray2: _p.gray2,
    gray3: _p.gray3,
    gray4: _p.gray4,
    contrast1: _p.contrast1,
    contrast2: _p.contrast2,
    contrast3: _p.contrast3,
    contrast4: _p.contrast4,
    staticBlack1: _p.staticBlack1,
    staticBlack2: _p.staticBlack2,
    staticBlack3: _p.staticBlack3,
    staticWhite: _p.staticWhite,
    purple1: _p.purple1,
    purple2: _p.purple2,
    purple3: _p.purple3,
    purple4: _p.purple4,
    accentMainDefault: _p.accentMainDefault,
  );

  late final _colorScheme = ColorScheme.fromSeed(
    seedColor: _p.accent,
    brightness: _p.brightness,
  );

  late final _checkboxThemeData = CheckboxThemeData(
    fillColor: WidgetStateProperty.resolveWith(
      (states) {
        if (states.contains(WidgetState.selected) && !states.contains(WidgetState.disabled)) return _p.accent;
        if (states.contains(WidgetState.selected) && states.contains(WidgetState.disabled)) return _p.accentDisabled;

        return null;
      },
    ),
    checkColor: WidgetStateProperty.all(_p.specialStaticWhite),
    side: WidgetStateBorderSide.resolveWith(
      (states) {
        if (!states.contains(WidgetState.selected) && !states.contains(WidgetState.disabled)) {
          return BorderSide(width: 2, color: _p.neutralLight);
        }
        if (!states.contains(WidgetState.selected) && states.contains(WidgetState.disabled)) {
          return BorderSide(width: 2, color: _p.neutralLightDisabled);
        }

        return null;
      },
    ),
    overlayColor: WidgetStateProperty.resolveWith(
      (states) {
        if (states.contains(WidgetState.pressed)) return _p.accentPressed.withValues(alpha: 0.2);

        if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) return _p.backgroundSystem;

        return _p.staticTransparent;
      },
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(2.0),
    ),
  );

  late final _iconButtonThemeData = IconButtonThemeData(
    style: ButtonStyle(
      shape: const WidgetStatePropertyAll(
        CircleBorder(),
      ),
      foregroundColor: WidgetStatePropertyAll(
        _p.specialStaticWhite,
      ),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) {
          if (states.contains(WidgetState.pressed) || states.contains(WidgetState.focused)) return _p.backgroundHover;
          if (states.contains(WidgetState.hovered)) return _p.backgroundPressed;

          return null;
        },
      ),
      mouseCursor: WidgetStateProperty.resolveWith(
        (states) {
          if (states.contains(WidgetState.disabled)) return SystemMouseCursors.basic;

          return null;
        },
      ),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
      iconSize: const WidgetStatePropertyAll(24),
    ),
  );

  late final _radioThemeData = RadioThemeData(
    fillColor: WidgetStateProperty.resolveWith(
      (states) {
        if (states.contains(WidgetState.disabled)) return _p.neutralBlack.withValues(alpha: 0.38);
        if (states.contains(WidgetState.selected)) return _p.accent;

        return _p.neutralBlack;
      },
    ),
    overlayColor: WidgetStateProperty.resolveWith(
      (states) {
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused) ||
            states.contains(WidgetState.pressed))
          return _p.backgroundSystem;

        return _p.staticTransparent;
      },
    ),
  );

  late final _floatingActionButtonThemeData = FloatingActionButtonThemeData(
    backgroundColor: _p.accent,
    extendedTextStyle: _textTheme.labelLarge?.copyWith(color: _p.specialStaticWhite),
    foregroundColor: _p.specialStaticWhite,
    iconSize: 24,
    extendedSizeConstraints: const BoxConstraints(minHeight: 56),
    smallSizeConstraints: const BoxConstraints(minHeight: 40, minWidth: 40),
    sizeConstraints: const BoxConstraints(minHeight: 56, minWidth: 56),
    largeSizeConstraints: const BoxConstraints(minHeight: 96, minWidth: 96),
    focusColor: _p.accentHover,
    hoverColor: _p.accentHover,
    splashColor: _p.accentPressed,
    hoverElevation: 4,
    elevation: 3,
    focusElevation: 3,
    disabledElevation: 3,
    highlightElevation: 3,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
  );

  late final _switchThemeData = SwitchThemeData(
    trackColor: WidgetStateProperty.resolveWith(
      (states) {
        if (states.contains(WidgetState.selected)) return _p.accentMainDefault;

        return _p.background2;
      },
    ),
    thumbColor: WidgetStateProperty.resolveWith(
      (states) {
        if (states.contains(WidgetState.selected)) return _p.staticWhite;
        if (states.contains(WidgetState.disabled)) return _p.contrast4;

        return _p.contrast1;
      },
    ),
    overlayColor: WidgetStatePropertyAll(_p.staticTransparent),
    trackOutlineWidth: WidgetStateProperty.resolveWith(
      (states) {
        if (!states.contains(WidgetState.selected)) return 2;

        return 0;
      },
    ),
    trackOutlineColor: WidgetStateProperty.resolveWith(
      (states) {
        if (states.contains(WidgetState.selected)) return null;

        if (states.contains(WidgetState.disabled)) return _p.gray1;

        return _p.contrast1;
      },
    ),
  );

  late final _snackBarThemeData = SnackBarThemeData(
    backgroundColor: _p.snackBarBackground,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
    ),
    behavior: SnackBarBehavior.floating,
    elevation: 3,
    contentTextStyle: _textTheme.bodyMedium?.copyWith(color: _p.specialStaticWhite),
    actionTextColor: _p.accentAdditional,
    closeIconColor: _p.specialStaticWhite,
  );

  late final _badgeThemeData = BadgeThemeData(
    textColor: _p.specialStaticWhite,
    textStyle: _textTheme.labelSmall,
    backgroundColor: _p.error,
    smallSize: 6,
    largeSize: 16,
    padding: const EdgeInsets.symmetric(horizontal: 4),
  );

  late final _customFilledButtonTheme = CustomFilledButtonTheme(
    danger: FilledButtonThemeData(
      style: _filledButtonTheme.style?.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(WidgetState.disabled)) return _p.error.withValues(alpha: 0.5);

            return _p.error;
          },
        ),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(WidgetState.pressed)) return _p.errorPressed;
            if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) return _p.errorHover;

            return null;
          },
        ),
      ),
    ),
    attention: FilledButtonThemeData(
      style: _filledButtonTheme.style?.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(WidgetState.disabled)) return _p.attention.withValues(alpha: 0.5);

            return _p.attention;
          },
        ),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(WidgetState.pressed)) return _p.attentionPressed;
            if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) return _p.attentionHover;

            return null;
          },
        ),
      ),
    ),
    iconButton: FilledButtonThemeData(
      style: _filledButtonTheme.style?.copyWith(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.only(top: 10, bottom: 10, left: 16, right: 24),
        ),
      ),
    ),
  );

  late final _customElevatedButtonTheme = CustomElevatedButtonTheme(
    iconButton: ElevatedButtonThemeData(
      style: _filledButtonTheme.style?.copyWith(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.only(top: 10, bottom: 10, left: 16, right: 24),
        ),
      ),
    ),
  );

  late final _customOutlinedButtonTheme = CustomOutlinedButtonTheme(
    iconButton: OutlinedButtonThemeData(
      style: _outlinedButtonThemeData.style?.copyWith(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.only(top: 10, bottom: 10, left: 16, right: 24),
        ),
      ),
    ),
  );

  late final _customTextButtonTheme = CustomTextButtonTheme(
    danger: TextButtonThemeData(
      style: _textButtonThemeData.style?.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(WidgetState.disabled)) return _p.errorDisabled.withValues(alpha: 0.5);

            return _p.error;
          },
        ),
      ),
    ),
    attention: TextButtonThemeData(
      style: _textButtonThemeData.style?.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(WidgetState.disabled)) return _p.attentionDisabled.withValues(alpha: 0.5);

            return _p.attention;
          },
        ),
      ),
    ),
    success: TextButtonThemeData(
      style: _textButtonThemeData.style?.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(WidgetState.disabled)) return _p.accentDisabled.withValues(alpha: 0.5);

            return _p.accent;
          },
        ),
      ),
    ),
    iconButton: _textButtonThemeData,
  );

  late final _elevatedButtonTheme = ElevatedButtonThemeData(
    style: _filledButtonTheme.style,
  );

  late final _filledButtonTheme = FilledButtonThemeData(
    style: ButtonStyle(
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(100),
        ),
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) {
          if (states.contains(WidgetState.disabled)) return _p.accentDisabled.withValues(alpha: 0.4);

          return _p.accent;
        },
      ),
      foregroundColor: WidgetStatePropertyAll(_p.specialStaticWhite),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) {
          if (states.contains(WidgetState.pressed)) return _p.accentPressed;
          if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) return _p.accentHover;

          return null;
        },
      ),
      textStyle: WidgetStatePropertyAll(_textTheme.labelLarge),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      ),
      iconSize: const WidgetStatePropertyAll(18),
      minimumSize: WidgetStatePropertyAll(
        Size(_buttonTheme.minWidth, _buttonTheme.height),
      ),
      visualDensity: VisualDensity.standard,
    ),
  );

  late final _outlinedButtonThemeData = OutlinedButtonThemeData(
    style: _filledButtonTheme.style?.copyWith(
      backgroundColor: WidgetStatePropertyAll(_p.staticTransparent),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) {
          if (states.contains(WidgetState.disabled)) return _p.neutralLight;

          return _p.neutralBlack;
        },
      ),
      shape: WidgetStateProperty.resolveWith(
        (states) {
          final Color borderColor;

          if (states.contains(WidgetState.disabled)) {
            borderColor = _p.neutralLight;
          } else {
            borderColor = _p.neutralBlack;
          }

          return StadiumBorder(
            side: BorderSide(
              color: borderColor,
            ),
          );
        },
      ),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) {
          if (states.contains(WidgetState.pressed)) return _p.backgroundPressed;
          if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) return _p.backgroundHover;

          return null;
        },
      ),
    ),
  );

  late final _textButtonThemeData = TextButtonThemeData(
    style: _filledButtonTheme.style?.copyWith(
      backgroundColor: WidgetStatePropertyAll(_p.staticTransparent),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) {
          if (states.contains(WidgetState.disabled)) return _p.neutralLight;

          return _p.neutralBlack;
        },
      ),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) {
          if (states.contains(WidgetState.pressed)) return _p.backgroundPressed;
          if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) return _p.backgroundHover;

          return _p.staticTransparent;
        },
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      textStyle: WidgetStatePropertyAll(
        _textTheme.labelLarge,
      ),
    ),
  );

  late final appSystemUiOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: _p.background,
    statusBarIconBrightness: _p.brightness == Brightness.dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: _p.brightness,
    systemStatusBarContrastEnforced: false,
  );

  late final _appBarTheme = AppBarTheme(
    backgroundColor: _p.staticTransparent,
    surfaceTintColor: _p.staticTransparent,
    shadowColor: _p.staticTransparent,
    systemOverlayStyle: appSystemUiOverlayStyle,
    elevation: 0,
    scrolledUnderElevation: 0,
    titleTextStyle: _textTheme.titleLarge,
    centerTitle: true,
    foregroundColor: _p.neutralBlack,
  );

  late final _navigationBarThemeData = NavigationBarThemeData(
    backgroundColor: _p.backgroundSystem,
    indicatorColor: _p.blendHover,
  );

  late final _popupMenuThemeData = PopupMenuThemeData(
    color: _p.background,
    position: PopupMenuPosition.under,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4.0),
    ),
    surfaceTintColor: _p.background,

    elevation: 2,
    textStyle: _textTheme.bodyLarge?.copyWith(
      color: _p.neutralBlack,
    ),
  );

  late final _menuButtonThemeData = MenuButtonThemeData(
    style: _textButtonThemeData.style?.copyWith(
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
      ),
      textStyle: WidgetStatePropertyAll(_textTheme.bodyLarge),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) {
          if (states.contains(WidgetState.disabled)) return _p.staticTransparent;
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused) ||
              states.contains(WidgetState.selected))
            return _p.backgroundSystemHover;
          if (states.contains(WidgetState.pressed)) return _p.backgroundSystemPressed;

          return null;
        },
      ),
    ),
  );

  late final _menuBarThemeData = MenuBarThemeData(
    style: MenuStyle(
      backgroundColor: WidgetStatePropertyAll(_p.background),
      surfaceTintColor: WidgetStatePropertyAll(_p.staticTransparent),
    ),
  );

  late final _dropdownMenuThemeData = DropdownMenuThemeData(
    textStyle: _textTheme.bodyLarge,
    inputDecorationTheme: _inputDecorationTheme,
    menuStyle: MenuStyle(
      backgroundColor: WidgetStatePropertyAll(_p.background),
      surfaceTintColor: WidgetStatePropertyAll(_p.staticTransparent),
      visualDensity: VisualDensity.standard,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: 8),
      ),
    ),
  );

  late final _menuThemeData = MenuThemeData(
    style: MenuStyle(
      backgroundColor: WidgetStatePropertyAll(_p.background),
      surfaceTintColor: WidgetStatePropertyAll(_p.staticTransparent),
    ),
  );

  late final _progressIndicatorThemeData = ProgressIndicatorThemeData(
    color: _p.accent,
    circularTrackColor: _p.blend.withValues(alpha: 0.2),
    linearTrackColor: _p.blend.withValues(alpha: 0.2),
    linearMinHeight: 4,
  );

  late final _inputDecorationTheme = InputDecorationTheme(
    filled: true,
    disabledBorder: OutlineInputBorder(
      borderSide: BorderSide(
        color: _p.neutralDarkDisabled.withValues(
          alpha: 0.3,
        ),
      ),
    ),
    errorBorder: OutlineInputBorder(
      borderSide: BorderSide(color: _p.error),
    ),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(
        color: _p.dumInputDecorationIdleColor,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(
        color: _p.neutralDark,
        width: 3,
      ),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderSide: BorderSide(color: _p.error, width: 3),
    ),
    outlineBorder: BorderSide(
      color: _p.dumInputDecorationIdleColor,
    ),
    border: OutlineInputBorder(
      borderSide: BorderSide(
        color: _p.dumInputDecorationIdleColor,
      ),
    ),
    floatingLabelStyle: WidgetStateTextStyle.resolveWith(
      (states) {
        if (states.contains(WidgetState.disabled)) {
          return _textTheme.bodySmall!.copyWith(color: _p.neutralBlackDisabled.withValues(alpha: 0.4));
        }

        if (states.contains(WidgetState.error)) {
          return _textTheme.bodySmall!.copyWith(color: _p.error);
        }

        return _textTheme.bodySmall!;
      },
    ),
    labelStyle: WidgetStateTextStyle.resolveWith(
      (states) {
        if (states.contains(WidgetState.disabled)) {
          return _textTheme.bodySmall!.copyWith(color: _p.neutralBlackDisabled.withValues(alpha: 0.3));
        }

        if (states.contains(WidgetState.error)) {
          return _textTheme.bodySmall!.copyWith(color: _p.error);
        }

        return _textTheme.bodySmall!;
      },
    ),
    alignLabelWithHint: true,
    hoverColor: _p.backgroundSystem,
    fillColor: _p.staticTransparent,
    iconColor: _p.neutralBlack,
    prefixIconColor: WidgetStateColor.resolveWith(
      (states) {
        if (states.contains(WidgetState.disabled)) {
          return _p.neutralBlackDisabled;
        }

        return _p.neutralBlack;
      },
    ),
    suffixIconColor: WidgetStateColor.resolveWith(
      (states) {
        if (states.contains(WidgetState.disabled)) {
          return _p.neutralBlackDisabled;
        }

        if (states.contains(WidgetState.error)) {
          return _p.error;
        }

        return _p.neutralBlack;
      },
    ),
    errorStyle: _textTheme.bodySmall?.copyWith(color: _p.error),
    hintStyle: WidgetStateTextStyle.resolveWith(
      (states) {
        final Color textColor;
        if (states.contains(WidgetState.disabled)) {
          textColor = _p.neutralDarkDisabled.withValues(alpha: 0.4);
        } else {
          textColor = _p.dumInputDecorationIdleColor;
        }

        return _textTheme.bodyLarge!.copyWith(color: textColor);
      },
    ),
    helperStyle: WidgetStateTextStyle.resolveWith(
      (states) {
        if (states.contains(WidgetState.disabled)) {
          return _textTheme.bodySmall!.copyWith(color: _p.neutralBlackDisabled.withValues(alpha: 0.3));
        }

        if (states.contains(WidgetState.error)) {
          return _textTheme.bodySmall!.copyWith(color: _p.error);
        }

        return _textTheme.bodySmall!;
      },
    ),
    counterStyle: WidgetStateTextStyle.resolveWith((states) => _textTheme.bodySmall!),
    contentPadding: const EdgeInsets.only(top: 16, bottom: 16, left: 16),
    floatingLabelBehavior: FloatingLabelBehavior.always,
    focusColor: _p.staticTransparent,
  );

  late final _textSelectionTheme = TextSelectionThemeData(
    cursorColor: WidgetStateColor.resolveWith(
      (states) {
        if (states.contains(WidgetState.error)) {
          return _p.error;
        }

        return _p.neutralBlack;
      },
    ),
    selectionColor: _p.blend,
    selectionHandleColor: _p.accent,
  );

  late final _dividerThemeData = DividerThemeData(
    color: _p.neutralBlend,
    space: 1,
  );

  late final _iconThemeData = IconThemeData(
    size: 24,
    color: _p.neutralBlack,
  );

  late final _navigationRailThemeData = NavigationRailThemeData(
    // Same pill as the phone's bottom bar.
    indicatorColor: _p.blendHover,
    unselectedLabelTextStyle: _textTheme.labelMedium,
    selectedLabelTextStyle: _textTheme.labelMedium,
    backgroundColor: _p.backgroundSystem,
  );

  late final _actionIconThemeData = ActionIconThemeData(
    closeButtonIconBuilder: (context) => CustomIcon.medium(
      icon: AssetIcons.close,
      color: _p.neutralBlack,
    ),
    backButtonIconBuilder: (context) => CustomIcon.medium(
      icon: AssetIcons.arrowBack,
      color: _p.neutralBlack,
    ),
  );

  late final _listTileThemeData = ListTileThemeData(
    contentPadding: const EdgeInsets.all(16),
    titleTextStyle: _textTheme.titleSmall,
    subtitleTextStyle: _textTheme.bodyMedium?.copyWith(color: _p.neutralLight),
  );

  late final _customDropdownMenuTheme = CustomDropdownMenuTheme(
    enabled: _dropdownMenuThemeData,
    disabled: _dropdownMenuThemeData.copyWith(
      textStyle: _dropdownMenuThemeData.textStyle?.copyWith(
        color: _p.neutralBlackDisabled.withValues(alpha: 0.4),
      ),
    ),
  );

  late final _tabBarTheme = TabBarThemeData(
    labelColor: _p.accent,
    unselectedLabelColor: _p.neutralBlack,
    indicatorColor: _p.accent,
    labelPadding: const EdgeInsets.symmetric(
      vertical: 12,
      horizontal: 16,
    ),
    labelStyle: _textTheme.titleSmall,
  );

  late final _dialogTheme = DialogThemeData(
    backgroundColor: _p.background,
    surfaceTintColor: _p.staticTransparent,
    titleTextStyle: _textTheme.headlineSmall,
    contentTextStyle: _textTheme.bodyMedium,
    iconColor: _p.accent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(
        Radius.circular(28.0),
      ),
    ),
  );

  late final _textTheme = TextTheme(
    displayLarge: TextStyle(
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      color: _p.neutralBlack,
      fontSize: 57,
      letterSpacing: -0.25,
      height: 1.12,
      fontFamily: FontFamilies.roboto,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    displayMedium: TextStyle(
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      color: _p.neutralBlack,
      fontSize: 45,
      height: 1.15,
      fontFamily: FontFamilies.roboto,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    displaySmall: TextStyle(
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      color: _p.neutralBlack,
      fontSize: 36,
      height: 1.22,
      fontFamily: FontFamilies.roboto,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    headlineLarge: TextStyle(
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      color: _p.neutralBlack,
      fontSize: 32,
      height: 1.25,
      fontFamily: FontFamilies.roboto,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    headlineMedium: TextStyle(
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      color: _p.neutralBlack,
      fontSize: 28,
      height: 1.28,
      fontFamily: FontFamilies.roboto,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    headlineSmall: TextStyle(
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      color: _p.neutralBlack,
      fontSize: 24,
      height: 1.33,
      fontFamily: FontFamilies.roboto,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    titleLarge: TextStyle(
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      color: _p.neutralBlack,
      fontSize: 22,
      height: 1.27,
      fontFamily: FontFamilies.roboto,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    titleMedium: TextStyle(
      fontWeight: FontWeight.w500,
      fontStyle: FontStyle.normal,
      color: _p.neutralBlack,
      fontSize: 16,
      letterSpacing: 0.15,
      height: 1.5,
      fontFamily: FontFamilies.roboto,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    titleSmall: TextStyle(
      fontWeight: FontWeight.w500,
      fontStyle: FontStyle.normal,
      color: _p.neutralBlack,
      fontSize: 14,
      letterSpacing: 0.1,
      height: 1.42,
      fontFamily: FontFamilies.roboto,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    labelLarge: TextStyle(
      fontWeight: FontWeight.w500,
      fontStyle: FontStyle.normal,
      color: _p.neutralBlack,
      fontSize: 14,
      letterSpacing: 0.1,
      height: 1.42,
      fontFamily: FontFamilies.roboto,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    labelMedium: TextStyle(
      fontWeight: FontWeight.w500,
      fontStyle: FontStyle.normal,
      color: _p.neutralBlack,
      fontSize: 12,
      letterSpacing: 0.5,
      height: 1.33,
      fontFamily: FontFamilies.roboto,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    labelSmall: TextStyle(
      fontWeight: FontWeight.w500,
      fontStyle: FontStyle.normal,
      color: _p.neutralBlack,
      fontSize: 11,
      letterSpacing: 0.5,
      height: 1.45,
      fontFamily: FontFamilies.roboto,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    bodyLarge: TextStyle(
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      color: _p.neutralBlack,
      fontSize: 16,
      letterSpacing: 0.5,
      height: 1.5,
      fontFamily: FontFamilies.roboto,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    bodyMedium: TextStyle(
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      color: _p.neutralBlack,
      fontSize: 14,
      letterSpacing: 0.25,
      height: 1.42,
      fontFamily: FontFamilies.roboto,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    bodySmall: TextStyle(
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      color: _p.neutralBlack,
      fontSize: 12,
      letterSpacing: 0.4,
      height: 1.33,
      fontFamily: FontFamilies.roboto,
      leadingDistribution: TextLeadingDistribution.even,
    ),
  );

  late final _buttonTheme = const ButtonThemeData(
    minWidth: 70,
    height: 40,
  );

  late final _customFilledIconButtonTheme = CustomFilledIconButtonTheme(
    iconButton: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(_p.specialStaticWhite),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(WidgetState.selected)) {
              return _p.accent;
            }

            return _p.neutralDark;
          },
        ),
      ),
    ),
    iconButtonInProgress: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(_p.specialStaticWhite),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(WidgetState.selected)) {
              return _p.accent;
            }

            return _p.neutralDark;
          },
        ),
      ),
    ),
  );

  late final _customMissSpelledTextTheme = CustomMissSpelledTextTheme(
    missSpelledStyle: TextStyle(
      decorationColor: _p.error,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.wavy,
      decorationThickness: 2,
    ),
  );

  ThemeData get data => ThemeData(
    // GENERAL CONFIGURATION
    useMaterial3: true,
    extensions: [
      _customColors,
      _customFilledButtonTheme,
      _customElevatedButtonTheme,
      _customOutlinedButtonTheme,
      _customTextButtonTheme,
      _customDropdownMenuTheme,
      _customFilledIconButtonTheme,
      _customMissSpelledTextTheme,
    ],

    // COLOR
    scaffoldBackgroundColor: _p.background,
    brightness: _p.brightness,
    primaryColor: _p.accent,
    colorScheme: _colorScheme,
    hoverColor: _p.staticTransparent,
    focusColor: _p.staticTransparent,

    // TYPOGRAPHY & ICONOGRAPHY
    textTheme: _textTheme,
    fontFamily: FontFamilies.roboto,
    iconTheme: _iconThemeData,
    textSelectionTheme: _textSelectionTheme,

    // COMPONENT THEMES
    checkboxTheme: _checkboxThemeData,
    iconButtonTheme: _iconButtonThemeData,
    radioTheme: _radioThemeData,
    floatingActionButtonTheme: _floatingActionButtonThemeData,
    switchTheme: _switchThemeData,
    snackBarTheme: _snackBarThemeData,
    badgeTheme: _badgeThemeData,
    elevatedButtonTheme: _elevatedButtonTheme,
    filledButtonTheme: _filledButtonTheme,
    outlinedButtonTheme: _outlinedButtonThemeData,
    textButtonTheme: _textButtonThemeData,
    dialogTheme: _dialogTheme,
    menuButtonTheme: _menuButtonThemeData,
    menuBarTheme: _menuBarThemeData,
    dropdownMenuTheme: _dropdownMenuThemeData,
    menuTheme: _menuThemeData,
    popupMenuTheme: _popupMenuThemeData,
    navigationBarTheme: _navigationBarThemeData,
    appBarTheme: _appBarTheme,
    progressIndicatorTheme: _progressIndicatorThemeData,
    inputDecorationTheme: _inputDecorationTheme,
    dividerTheme: _dividerThemeData,
    navigationRailTheme: _navigationRailThemeData,
    actionIconTheme: _actionIconThemeData,
    listTileTheme: _listTileThemeData,
    buttonTheme: _buttonTheme,
    tabBarTheme: _tabBarTheme,
  );
}
