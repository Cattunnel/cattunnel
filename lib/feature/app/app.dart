import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trusttunnel/common/constants/app_constants.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/app_locale_preferences.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/logging/observers/logging_navigator_observer.dart';
import 'package:trusttunnel/common/theme/appearance_preferences.dart';
import 'package:trusttunnel/feature/app/widgets/app_system_ui_shell.dart';
import 'package:trusttunnel/feature/navigation/navigation_screen.dart';
import 'package:trusttunnel/feature/security/domain/security_platform.dart';
import 'package:trusttunnel/feature/security/domain/security_settings.dart';
import 'package:trusttunnel/feature/security/widgets/app_lock_gate.dart';
import 'package:trusttunnel/feature/updates/widgets/update_watcher.dart';
import 'package:trusttunnel/feature/vpn/widgets/connection_watchdog.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    AppLocalePreferences.load(context.dependencyFactory.sharedPreferences);
    AppearancePreferences.load(context.dependencyFactory.sharedPreferences);
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([AppLocalePreferences.current, AppearancePreferences.themeMode]),
    builder: (context, _) => _buildApp(context, AppLocalePreferences.current.value.value ?? Localization.defaultLocale),
  );

  Widget _buildApp(BuildContext context, Locale locale) => MaterialApp(
    theme: context.dependencyFactory.lightThemeData,
    darkTheme: context.dependencyFactory.darkThemeData,
    themeMode: AppearancePreferences.themeMode.value,
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
