import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trusttunnel/common/constants/app_constants.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/app_locale_preferences.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/logging/observers/logging_navigator_observer.dart';
import 'package:trusttunnel/common/theme/appearance_preferences.dart';
import 'package:trusttunnel/common/utils/device_orientation_policy.dart';
import 'package:trusttunnel/feature/app/widgets/app_system_ui_shell.dart';
import 'package:trusttunnel/feature/navigation/navigation_screen.dart';
import 'package:trusttunnel/feature/security/domain/security_platform.dart';
import 'package:trusttunnel/feature/security/domain/security_settings.dart';
import 'package:trusttunnel/feature/security/widgets/app_lock_gate.dart';
import 'package:trusttunnel/feature/updates/widgets/update_watcher.dart';
import 'package:trusttunnel/feature/vpn/widgets/connection_watchdog.dart';
import 'package:trusttunnel/widgets/aero/aero_widgets.dart';
import 'package:trusttunnel/widgets/secure_screen.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(DeviceOrientationPolicy.apply());
    });
    AppLocalePreferences.load(context.dependencyFactory.sharedPreferences);
    AppearancePreferences.load(context.dependencyFactory.sharedPreferences);
    SecureScreen.allowScreenshots = SecuritySettings(context.dependencyFactory.sharedPreferences).allowScreenshots;
    unawaited(_syncDisguise());
  }

  /// The launcher alias is the source of truth for the disguise (it
  /// survives a panic wipe, which clears the preference that the
  /// notification title reads).
  Future<void> _syncDisguise() async {
    final settings = SecuritySettings(context.dependencyFactory.sharedPreferences);
    final disguised = await SecurityPlatform.isDisguised();
    if (disguised != settings.disguise) {
      await settings.setDisguise(disguised);
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    unawaited(DeviceOrientationPolicy.apply());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      AppLocalePreferences.current,
      AppearancePreferences.themeMode,
      AppearancePreferences.style,
      AeroClock.phase,
    ]),
    builder: (context, _) => _buildApp(context, AppLocalePreferences.current.value.value ?? Localization.defaultLocale),
  );

  // «Y2K» is dark only: its own theme for both slots, dark mode forced.
  bool get _y2k => AppearancePreferences.style.value == AppStyle.y2k;

  // «Аэро» follows the clock, not the light/dark setting: the night theme
  // from 21 to 5, the light one the rest of the day.
  bool get _aero => AppearancePreferences.style.value == AppStyle.aero;

  bool get _cityPop => AppearancePreferences.style.value == AppStyle.cityPop;

  ThemeData? get _ownTheme {
    final factory = context.dependencyFactory;
    if (_y2k) return factory.y2kThemeData;
    if (!_aero) return null;

    return AeroClock.phase.value == AeroPhase.night ? factory.aeroNightThemeData : factory.aeroThemeData;
  }

  Widget _buildApp(BuildContext context, Locale locale) {
    if (_aero) {
      AeroClock.start();
    } else {
      AeroClock.stop();
    }
    final own = _ownTheme;

    return _materialApp(context, locale, own);
  }

  Widget _materialApp(BuildContext context, Locale locale, ThemeData? own) => MaterialApp(
    // «City pop» keeps the light/dark setting: its paper theme or its night one.
    theme: own ?? (_cityPop ? context.dependencyFactory.cityPopThemeData : context.dependencyFactory.lightThemeData),
    darkTheme:
        own ?? (_cityPop ? context.dependencyFactory.cityPopNightThemeData : context.dependencyFactory.darkThemeData),
    themeMode: own != null ? ThemeMode.dark : AppearancePreferences.themeMode.value,
    navigatorObservers: [
      LoggingNavigatorObserver(
        navigatorName: 'root',
      ),
    ],
    home: const AppSystemUIShell(
      child: ConnectionWatchdog(
        child: UpdateWatcher(
          child: NavigationScreen(),
        ),
      ),
    ),
    // Above the Navigator, so the lock also covers dialogs and pop-ups.
    // Status bar icons follow the theme in effect (light/dark/system).
    builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).appBarTheme.systemOverlayStyle ?? SystemUiOverlayStyle.dark,
      child: AppLockGate(child: child ?? const SizedBox.shrink()),
    ),
    title: AppConstants.appName,
    locale: locale,
    localizationsDelegates: Localization.localizationDelegates,
    supportedLocales: Localization.supportedLocales,
  );
}
