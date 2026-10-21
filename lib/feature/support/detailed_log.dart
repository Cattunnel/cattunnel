import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/common/logging/enum/logging_level.dart';
import 'package:trusttunnel/common/logging/enum/logging_security_type.dart';
import 'package:trusttunnel/data/repository/logging_settings_repository.dart';
import 'package:trusttunnel/feature/settings/app_logging/widgets/scope/app_logging_scope_controller.dart';

/// The detailed log: ten minutes of everything the engine says.
///
/// The engine's log is at "info" by default, and the lines about what it
/// tried to connect are at "debug" - so the problem report says nothing
/// about the attempts, which is the first thing the admin asks for. The
/// detailed log puts the logs at "debug" (and stops stripping them), and
/// the setting it replaces comes back on its own.
///
/// The replaced setting is remembered, so an app that was closed with the
/// detailed log on does not keep logging everything forever: the next start
/// puts it back (see [restore]).
class DetailedLog {
  /// How long the detailed log stays on.
  static const duration = Duration(minutes: 10);

  static const _untilKey = 'detailed_log_until';
  static const _levelKey = 'detailed_log_level';
  static const _securityKey = 'detailed_log_security';

  static Timer? _timer;

  /// Whether the detailed log is on right now.
  static bool isOn(SharedPreferences preferences) {
    final until = preferences.getInt(_untilKey);

    return until != null && DateTime.now().millisecondsSinceEpoch < until;
  }

  /// When the detailed log goes off, if it is on.
  static DateTime? until(SharedPreferences preferences) {
    final until = preferences.getInt(_untilKey);

    return until == null ? null : DateTime.fromMillisecondsSinceEpoch(until);
  }

  /// The setting the detailed log replaced, still waiting to be put back.
  static ({LoggingLevel level, LoggingSecurityType security})? pending(SharedPreferences preferences) {
    final level = preferences.getInt(_levelKey);
    final security = preferences.getInt(_securityKey);
    if (level == null || security == null) return null;

    return (
      level: LoggingLevel.values[level.clamp(0, LoggingLevel.values.length - 1)],
      security: LoggingSecurityType.values[security.clamp(0, LoggingSecurityType.values.length - 1)],
    );
  }

  /// Turns the detailed log on and remembers the setting it replaces.
  static Future<void> enable(SharedPreferences preferences, AppLoggingScopeController logging) async {
    if (!isOn(preferences)) {
      await preferences.setInt(_levelKey, logging.loggingLevel.index);
      await preferences.setInt(_securityKey, logging.securityType.index);
    }
    await preferences.setInt(_untilKey, DateTime.now().add(duration).millisecondsSinceEpoch);
    logging.updateLoggingLevel(level: LoggingLevel.debug);
    logging.updateSecurityType(securityType: LoggingSecurityType.full);
    _startTimer(preferences, logging);
  }

  /// Turns it off now and puts the replaced setting back.
  static Future<void> disable(SharedPreferences preferences, AppLoggingScopeController logging) async {
    _timer?.cancel();
    _timer = null;
    await preferences.remove(_untilKey);
    final level = preferences.getInt(_levelKey);
    final security = preferences.getInt(_securityKey);
    await preferences.remove(_levelKey);
    await preferences.remove(_securityKey);
    if (level != null) {
      logging.updateLoggingLevel(level: LoggingLevel.values[level.clamp(0, LoggingLevel.values.length - 1)]);
    }
    if (security != null) {
      logging.updateSecurityType(
        securityType: LoggingSecurityType.values[security.clamp(0, LoggingSecurityType.values.length - 1)],
      );
    }
  }

  /// Puts the replaced setting back after the app was closed with the
  /// detailed log on: the time is up, but nobody was there to switch it off.
  static Future<void> restore(SharedPreferences preferences, LoggingSettingsRepository settings) async {
    final pending = DetailedLog.pending(preferences);
    if (pending == null) return;
    await preferences.remove(_untilKey);
    await preferences.remove(_levelKey);
    await preferences.remove(_securityKey);
    await settings.setLoggingLevel(pending.level);
    await settings.setSecurityType(pending.security);
  }

  static void _startTimer(SharedPreferences preferences, AppLoggingScopeController logging) {
    _timer?.cancel();
    _timer = Timer(duration, () {
      _timer = null;
      disable(preferences, logging).ignore();
    });
  }
}
