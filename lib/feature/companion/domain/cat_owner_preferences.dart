import 'package:shared_preferences/shared_preferences.dart';

enum CatOwnerGender { host, hostess }

/// The cat's tiny "memory" of who you are - a name and, for grammatically
/// correct Russian compliments, an optional gender. Stored purely in
/// SharedPreferences (on-device only; CatTunnel has no server to send it
/// to) and only ever used to personalize [catCompliments] text.
class CatOwnerPreferences {
  static const _introDoneKey = 'cat_owner_intro_done';
  static const _nameKey = 'cat_owner_name';
  static const _genderKey = 'cat_owner_gender';
  static const _sulkingUntilKey = 'cat_sulking_until';
  static const _petCountKey = 'cat_pet_count';
  static const _purrEnabledKey = 'cat_purr_enabled';

  /// How long Marsik refuses to be petted after storming off - deliberately
  /// not a round number.
  static const sulkDuration = Duration(hours: 4, minutes: 4);

  final SharedPreferences _preferences;

  const CatOwnerPreferences(this._preferences);

  bool get introDone => _preferences.getBool(_introDoneKey) ?? false;

  String? get name => _preferences.getString(_nameKey);

  CatOwnerGender? get gender {
    final value = _preferences.getString(_genderKey);

    return switch (value) {
      'host' => CatOwnerGender.host,
      'hostess' => CatOwnerGender.hostess,
      _ => null,
    };
  }

  Future<void> save({required String? name, required CatOwnerGender? gender}) async {
    await _preferences.setBool(_introDoneKey, true);

    final trimmedName = name?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      await _preferences.setString(_nameKey, trimmedName);
    }

    if (gender != null) {
      await _preferences.setString(_genderKey, gender.name);
    }
  }

  /// How much longer Marsik is sulking, or null if he's fine to pet.
  Duration? get sulkingRemaining {
    final untilMillis = _preferences.getInt(_sulkingUntilKey);
    if (untilMillis == null) {
      return null;
    }

    final remaining = DateTime.fromMillisecondsSinceEpoch(untilMillis).difference(DateTime.now());

    return remaining.isNegative ? null : remaining;
  }

  Future<void> startSulking() =>
      _preferences.setInt(_sulkingUntilKey, DateTime.now().add(sulkDuration).millisecondsSinceEpoch);

  /// Total strokes over all time, shown in [CatPettingDialog] and used for
  /// milestone easter eggs (see [catMilestoneLine]).
  int get petCount => _preferences.getInt(_petCountKey) ?? 0;

  Future<void> setPetCount(int count) => _preferences.setInt(_petCountKey, count);

  /// Purring while being petted - off by default, so he doesn't suddenly
  /// start purring out loud in public.
  bool get purrEnabled => _preferences.getBool(_purrEnabledKey) ?? false;

  Future<void> setPurrEnabled(bool enabled) => _preferences.setBool(_purrEnabledKey, enabled);
}
