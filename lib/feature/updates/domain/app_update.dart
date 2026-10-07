/// One APK of a release: the arm64 build most phones get, or the universal
/// fallback (armv7 + arm64) for old phones.
class AppUpdateApk {
  final Uri url;
  final String sha256;

  const AppUpdateApk({required this.url, required this.sha256});
}

/// A release described by latest.json next to the APKs on the download
/// server (see UpdateService):
///
/// ```json
/// {
///   "version": "1.3.6",
///   "build": 5,
///   "notes": "What's new, shown by Marsik",
///   "apks": {
///     "arm64-v8a": {"url": "https://…/cattunnel-1.3.6-arm64.apk", "sha256": "…"},
///     "universal": {"url": "https://…/cattunnel-1.3.6-universal.apk", "sha256": "…"}
///   }
/// }
/// ```
///
/// `build` is what gets compared (the version name carries suffixes like
/// "/S-Signed") - the Android versionCode of the release APKs. With
/// `--split-per-abi` that is 2000 + N for arm64 (N = the `+N` of pubspec),
/// and the universal APK is built with the same number (1.3.5 was 2004).
/// tools/make_latest_json.sh reads it from the APKs themselves.
class AppUpdate {
  final String version;
  final int build;
  final String notes;
  final Map<String, AppUpdateApk> apks;

  const AppUpdate({required this.version, required this.build, required this.notes, required this.apks});

  /// Throws [FormatException] on anything unexpected - a half-written or
  /// foreign file must never turn into an update offer.
  factory AppUpdate.fromJson(Object? json) {
    if (json is! Map<String, Object?>) throw const FormatException('latest.json: not an object');
    final version = json['version'];
    final build = json['build'];
    final notes = json['notes'] ?? '';
    final apks = json['apks'];
    if (version is! String || build is! int || notes is! String || apks is! Map<String, Object?>) {
      throw const FormatException('latest.json: bad fields');
    }

    return AppUpdate(
      version: version,
      build: build,
      notes: notes,
      apks: apks.map((abi, apk) {
        if (apk is! Map<String, Object?> || apk['url'] is! String || apk['sha256'] is! String) {
          throw FormatException('latest.json: bad apk "$abi"');
        }
        final url = Uri.parse(apk['url']! as String);
        final sha256 = (apk['sha256']! as String).toLowerCase();
        if (url.scheme != 'https' || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
          throw FormatException('latest.json: apk "$abi" must be https with a sha256');
        }

        return MapEntry(abi, AppUpdateApk(url: url, sha256: sha256));
      }),
    );
  }

  /// The APK for this phone: its best ABI if the release has a build for it,
  /// otherwise the universal one.
  AppUpdateApk? apkFor(List<String> supportedAbis) {
    for (final abi in supportedAbis) {
      final apk = apks[abi];
      if (apk != null) return apk;
    }

    return apks['universal'];
  }
}
