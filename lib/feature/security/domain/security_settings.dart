import 'package:shared_preferences/shared_preferences.dart';

/// Settings of the Cyber security section. All protective defaults are on
/// (user CAs NOT trusted); every optional feature is off until the user
/// turns it on.
///
/// Stored in the Flutter SharedPreferences, so native code (the QS tile)
/// can read them too as `flutter.<key>` in "FlutterSharedPreferences".
class SecuritySettings {
  static const trustUserCasKey = 'security_trust_user_cas';
  static const _panicButtonKey = 'security_panic_button';
  static const _appLockKey = 'security_app_lock';
  static const _disguiseKey = 'security_disguise';

  final SharedPreferences _preferences;

  const SecuritySettings(this._preferences);

  /// Off by default: the VPN engine then checks endpoints without a pinned
  /// certificate against the system roots only (see EndpointCaResolver).
  bool get trustUserCas => _preferences.getBool(trustUserCasKey) ?? false;

  Future<void> setTrustUserCas(bool value) => _preferences.setBool(trustUserCasKey, value);

  bool get panicButton => _preferences.getBool(_panicButtonKey) ?? false;

  Future<void> setPanicButton(bool value) => _preferences.setBool(_panicButtonKey, value);

  bool get appLock => _preferences.getBool(_appLockKey) ?? false;

  Future<void> setAppLock(bool value) => _preferences.setBool(_appLockKey, value);

  /// Mirrors the launcher alias state (the source of truth is the component
  /// setting, see SecurityPlatform.isDisguised) for Dart code that needs it
  /// synchronously, e.g. the notification title.
  bool get disguise => _preferences.getBool(_disguiseKey) ?? false;

  Future<void> setDisguise(bool value) => _preferences.setBool(_disguiseKey, value);
}
