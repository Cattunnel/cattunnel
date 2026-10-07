import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dage/dage.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:trusttunnel/common/utils/age_armor.dart';
import 'package:trusttunnel/common/utils/deep_link_uri_normalizer.dart';
import 'package:trusttunnel/common/utils/routing_profile_utils.dart';
import 'package:trusttunnel/data/datasources/server_datasource.dart';
import 'package:trusttunnel/data/datasources/subscription_datasource.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';

class SubscriptionFetchException implements Exception {
  final String message;

  /// HTTP status of the subscription server's reply, when it replied at all.
  final int? statusCode;

  const SubscriptionFetchException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// {@template subscription_sync_service}
/// Fetches a subscription's server list and reconciles it into the local
/// database.
///
/// The subscription body format is a newline-separated list of `tt://`
/// links (same encoding used for a single-server export/import), so
/// refreshing a subscription reuses [ServerDataSource.getServerByBase64]
/// per line rather than a bespoke parser.
///
/// The body may also carry one `#mirrors <url> <url> ...` line: the
/// server's current list of mirror URLs for this subscription, in the order
/// they should be tried. It replaces the stored list, so mirrors can be
/// added, reordered or dropped server-side. Builds that predate mirrors
/// skip the line like any other non-`tt://` line.
/// {@endtemplate}
class SubscriptionSyncService {
  static const _mirrorsDirective = '#mirrors';

  /// Per-mirror limit for connecting + TLS + response headers. Kept short on
  /// purpose: a blocked address usually hangs silently (the DPI drops the
  /// ClientHello instead of resetting), and every second here is a second
  /// before the next mirror gets a chance.
  static const _mirrorConnectTimeout = Duration(seconds: 7);

  /// Reading the body once the mirror has answered.
  static const _bodyTimeout = Duration(seconds: 20);

  final SubscriptionDataSource _subscriptionDataSource;
  final ServerDataSource _serverDataSource;

  SubscriptionSyncService({
    required SubscriptionDataSource subscriptionDataSource,
    required ServerDataSource serverDataSource,
  }) : _subscriptionDataSource = subscriptionDataSource,
       _serverDataSource = serverDataSource;

  /// {@macro subscription_sync_service}
  Future<void> refresh(SubscriptionData subscription) async {
    final id = subscription.id;

    if (id == null) {
      throw ArgumentError('Cannot refresh a subscription that has not been saved yet');
    }

    final bytes = await _fetch(subscription);
    final body = await _decode(bytes, subscription);
    final servers = await _parse(body);

    // An empty result would make the sync below delete every server of this
    // subscription except the selected one. Far more likely a broken response
    // (server-side error, a link format [_parse] silently skipped) than a
    // real "you have no servers" - keep what we have instead.
    if (servers.isEmpty) {
      throw const SubscriptionFetchException('Subscription returned no usable servers');
    }

    await _subscriptionDataSource.syncServersForSubscription(id: id, servers: servers);

    final mirrors = _parseMirrors(body);
    if (mirrors.isNotEmpty && SubscriptionData.joinUrls(mirrors) != SubscriptionData.joinUrls(subscription.urls)) {
      await _subscriptionDataSource.updateSubscription(
        id: id,
        request: subscription.copyWith(url: SubscriptionData.joinUrls(mirrors)),
      );
    }

    await _subscriptionDataSource.markRefreshed(id: id, at: DateTime.now());
  }

  /// Tries the subscription's mirrors in their fixed order; the first one
  /// that answers 200 wins.
  Future<Uint8List> _fetch(SubscriptionData subscription) async {
    final urls = subscription.urls;
    if (urls.isEmpty) {
      throw const SubscriptionFetchException('Subscription URL is empty');
    }

    SubscriptionFetchException? answered;
    Object? lastError;

    for (final url in urls) {
      try {
        return await _fetchOne(url, skipVerification: subscription.skipVerification);
      } on SubscriptionFetchException catch (e) {
        // A mirror that actually replied (e.g. 404 - token revoked) says
        // more than one that timed out, so that's what gets reported.
        if (e.statusCode != null) {
          answered ??= e;
        }
        lastError = e;
      } catch (e) {
        lastError = e;
      }
    }

    if (answered != null) {
      throw answered;
    }
    if (lastError is SubscriptionFetchException) {
      throw lastError;
    }
    throw SubscriptionFetchException('Subscription unreachable: $lastError');
  }

  Future<Uint8List> _fetchOne(String url, {required bool skipVerification}) async {
    // The response carries VPN credentials - never over cleartext, even for
    // an http:// subscription saved before this was enforced in the UI.
    // (Dart's HttpClient doesn't honor Android's cleartext policy.)
    if (Uri.tryParse(url)?.scheme != 'https') {
      throw const SubscriptionFetchException('Subscription URL must use https://');
    }

    final client = _buildClient(skipVerification: skipVerification);

    try {
      // No redirects: a 3xx could otherwise hop the request (and later the
      // credentials) over to plain http or another host.
      final request = http.Request('GET', Uri.parse(url))..followRedirects = false;
      final response = await http.Response.fromStream(
        await client.send(request).timeout(_mirrorConnectTimeout),
      ).timeout(_bodyTimeout);

      if (response.statusCode != 200) {
        throw SubscriptionFetchException(
          'Subscription server returned HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      return response.bodyBytes;
    } finally {
      client.close();
    }
  }

  /// The `#mirrors` line of [body], https URLs only; empty if absent.
  List<String> _parseMirrors(String body) {
    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (!line.startsWith(_mirrorsDirective)) {
        continue;
      }

      return SubscriptionData.splitUrls(line.substring(_mirrorsDirective.length))
          .where((url) => Uri.tryParse(url)?.scheme == 'https' && Uri.parse(url).host.isNotEmpty)
          .toList();
    }

    return const [];
  }

  /// Decodes the raw response into the newline-separated `tt://` link text.
  ///
  /// If [SubscriptionData.agePrivateKey] is set, [bytes] are treated as an
  /// age-encrypted (age-encryption.org/v1) payload and decrypted with that
  /// X25519 identity first - so a passive observer or active DPI probe of
  /// the subscription URL sees only opaque ciphertext, never the server
  /// list. Both the binary and the ASCII-armored age formats are accepted.
  Future<String> _decode(Uint8List bytes, SubscriptionData subscription) async {
    final agePrivateKey = subscription.agePrivateKey;
    if (agePrivateKey == null || agePrivateKey.isEmpty) {
      return utf8.decode(bytes);
    }

    try {
      final identity = AgeIdentity.fromBech32(agePrivateKey.trim());
      final keyPair = await AgePlugin.convertIdentityToKeyPair(identity);

      final binary = AgeArmor.isArmored(bytes) ? AgeArmor.decode(bytes) : bytes;
      final chunks = await decrypt(Stream.value(binary), [keyPair]).toList();
      final decrypted = chunks.expand((chunk) => chunk).toList();

      return utf8.decode(decrypted);
    } on SubscriptionFetchException {
      rethrow;
    } catch (_) {
      throw const SubscriptionFetchException('Failed to decrypt subscription - check the age key');
    }
  }

  /// Builds an HTTP client scoped to a single subscription.
  ///
  /// [skipVerification] only relaxes certificate checks for requests made by
  /// this client instance - it never affects any other subscription or the
  /// VPN connection's own TLS handling.
  http.Client _buildClient({required bool skipVerification}) {
    if (!skipVerification) {
      return http.Client();
    }

    final httpClient = HttpClient()..badCertificateCallback = (certificate, host, port) => true;

    return IOClient(httpClient);
  }

  Future<List<ServerData>> _parse(String body) async {
    final lines = body.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty);

    final servers = <ServerData>[];

    for (final line in lines) {
      final normalized = DeepLinkUriNormalizer.normalize(line);
      if (normalized == null) {
        continue;
      }

      try {
        servers.add(
          await _serverDataSource.getServerByBase64(
            base64: normalized,
            routingProfileId: RoutingProfileUtils.defaultRoutingProfileId,
          ),
        );
      } catch (_) {
        // Skip a malformed entry rather than failing the whole refresh.
        continue;
      }
    }

    return servers;
  }
}
