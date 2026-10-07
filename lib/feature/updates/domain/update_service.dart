import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/feature/updates/domain/app_update.dart';

/// Where latest.json lives, given at build time only:
///   `--dart-define=UPDATE_URL=https://…/latest.json`
/// Never hardcoded, so the source doesn't name our servers. Without it (or
/// with a non-https value) the whole update feature is off.
const _updateUrl = String.fromEnvironment('UPDATE_URL');

/// Ed25519 public key (base64, 32 bytes) that signs latest.json, also given
/// at build time: `--dart-define=UPDATE_PUBKEY=…` (tools/sign_latest_json.sh
/// prints it). Without a valid key updates are off - an unsigned
/// latest.json is never trusted.
const _updatePublicKey = String.fromEnvironment('UPDATE_PUBKEY');

/// In-app updates: read latest.json, check its signature (`latest.json.sig`
/// next to it), compare its `build` with ours, download the file into
/// cache/updates/ and let UpdatePlatform check the hash and install it.
///
/// Android takes the APK from latest.json. Windows reads its own
/// `latest-windows.json` (same format and key, `apks.windows-x64` = the
/// installer), so the phones' file stays as it is.
class UpdateService {
  static const _lastCheckKey = 'update_last_check_ms';
  static const _autoCheckEvery = Duration(hours: 20);
  static const _checkTimeout = Duration(seconds: 10);
  static String get _fileName => Platform.isWindows ? 'CatTunnel-Setup.exe' : 'cattunnel-update.apk';

  static String get _manifestUrl =>
      Platform.isWindows ? _updateUrl.replaceFirst(RegExp(r'\.json$'), '-windows.json') : _updateUrl;

  const UpdateService._();

  static bool get enabled =>
      (Platform.isAndroid || Platform.isWindows) &&
      Uri.tryParse(_updateUrl)?.scheme == 'https' &&
      _publicKey != null;

  static final List<int>? _publicKey = () {
    try {
      final key = base64.decode(_updatePublicKey);

      return key.length == 32 ? key : null;
    } on FormatException {
      return null;
    }
  }();

  /// The automatic check on launch runs at most about once a day.
  static Future<bool> autoCheckDue() async {
    if (!enabled) return false;
    final preferences = await SharedPreferences.getInstance();
    final last = preferences.getInt(_lastCheckKey);

    return last == null ||
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last)) >= _autoCheckEvery;
  }

  /// A newer release, or null when we're up to date. Throws on network or
  /// format errors - the caller decides whether to say so (manual check) or
  /// stay quiet (automatic one).
  static Future<AppUpdate?> check() async {
    final (response, signature) = await (
      http.get(Uri.parse(_manifestUrl)).timeout(_checkTimeout),
      http.get(Uri.parse('$_manifestUrl.sig')).timeout(_checkTimeout),
    ).wait;
    if (response.statusCode != 200) throw HttpException('latest.json: HTTP ${response.statusCode}');
    if (signature.statusCode != 200) throw HttpException('latest.json.sig: HTTP ${signature.statusCode}');
    await _verify(response.bodyBytes, signature.body);

    final update = AppUpdate.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    final current = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);

    return update.build > current ? update : null;
  }

  /// Throws [FormatException] unless [signature] is our key's signature of
  /// exactly these bytes.
  static Future<void> _verify(List<int> body, String signature) async {
    if (!await signatureValid(body, signature, _publicKey!)) {
      throw const FormatException('latest.json: bad signature');
    }
  }

  /// Whether [signature] (base64, as tools/sign_latest_json.sh writes it) is
  /// an Ed25519 signature of [body] by [publicKey].
  @visibleForTesting
  static Future<bool> signatureValid(List<int> body, String signature, List<int> publicKey) async {
    final List<int> bytes;
    try {
      bytes = base64.decode(signature.trim());
    } on FormatException {
      return false;
    }
    if (bytes.length != 64) return false;

    return Ed25519().verify(
      body,
      signature: Signature(bytes, publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519)),
    );
  }

  /// Downloads [apk] into cache/updates/ (replacing an older download) and
  /// returns the file. [onProgress] gets 0..1, or null while the size is
  /// unknown.
  static Future<File> download(AppUpdateApk apk, {required ValueChanged<double?> onProgress}) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final file = File('${dir.path}/$_fileName');

    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', apk.url)).timeout(_checkTimeout);
      if (response.statusCode != 200) throw HttpException('APK: HTTP ${response.statusCode}');

      final total = response.contentLength;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(total == null || total == 0 ? null : received / total);
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }

    return file;
  }
}
