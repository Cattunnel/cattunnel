import 'package:dage/dage.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';

/// `cattunnel://subscription?url=...&key=...&name=...` - a whole subscription
/// (URL + optional age key + name) in one string, for sharing as a QR code
/// between phones and importing it with the in-app scanner.
///
/// Decoding is strict (https only, valid age identity) and only ever feeds a
/// pre-filled add-subscription form - nothing is saved without the user
/// confirming it.
abstract final class SubscriptionShareLink {
  static const _scheme = 'cattunnel';
  static const _host = 'subscription';

  static String encode(SubscriptionData subscription) => Uri(
    scheme: _scheme,
    host: _host,
    queryParameters: {
      'url': subscription.url,
      if (subscription.agePrivateKey case final key? when key.isNotEmpty) 'key': key,
      'name': subscription.name,
    },
  ).toString();

  /// The subscription encoded in [raw], or `null` if it isn't a valid
  /// share link.
  static SubscriptionData? tryDecode(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != _scheme || uri.host != _host) {
      return null;
    }

    // May be several mirrors ("a | b"), see SubscriptionData.urls.
    final urls = SubscriptionData.splitUrls(uri.queryParameters['url'] ?? '').map(Uri.tryParse).toList();
    if (urls.isEmpty || urls.any((url) => url == null || url.scheme != 'https' || url.host.isEmpty)) {
      return null;
    }
    final url = urls.first!;

    final key = uri.queryParameters['key']?.trim();
    if (key != null && key.isNotEmpty) {
      try {
        AgeIdentity.fromBech32(key);
      } catch (_) {
        return null;
      }
    }

    final name = uri.queryParameters['name']?.trim();

    return SubscriptionData(
      name: name == null || name.isEmpty ? url.host : name,
      url: SubscriptionData.joinUrls(urls.map((url) => url.toString()).toList()),
      agePrivateKey: key == null || key.isEmpty ? null : key,
    );
  }
}
