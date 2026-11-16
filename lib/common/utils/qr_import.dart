import 'package:trusttunnel/common/utils/deep_link_uri_normalizer.dart';
import 'package:trusttunnel/common/utils/subscription_share_link.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';

/// What a scanned QR code holds.
sealed class QrImport {
  const QrImport();

  /// Classifies [raw] without touching the network or the database.
  ///
  /// Returns `null` for text that is not a link the app can import.
  static QrImport? tryParse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return null;
    }

    final code = SubscriptionShareLink.tryDecodeCode(text);
    if (code != null) {
      return QrImportSubscriptionCode(code: code.code, base: code.base);
    }

    final subscription = SubscriptionShareLink.tryDecode(text);
    if (subscription != null) {
      return QrImportSubscriptionLink(subscription);
    }

    final oneTimePage = _parseOneTimePage(text);
    if (oneTimePage != null) {
      return oneTimePage;
    }

    final serverLink = DeepLinkUriNormalizer.normalize(text);
    if (serverLink != null) {
      return QrImportServerLink(serverLink);
    }

    return null;
  }

  /// `https://<host>/api/go/<code>` is the page the bot sends in Telegram;
  /// the QR on that page is the same one-time code with the base `https://<host>`.
  static QrImportSubscriptionCode? _parseOneTimePage(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return null;
    }

    final segments = uri.pathSegments;
    if (segments.length != 3 || segments[0] != 'api' || segments[1] != 'go') {
      return null;
    }

    final code = segments[2].trim();
    if (code.isEmpty) {
      return null;
    }

    final base = Uri(
      scheme: 'https',
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString();

    return QrImportSubscriptionCode(code: code, base: base);
  }
}

/// A `tt://` server link, already normalized for [DeepLinkRepository].
final class QrImportServerLink extends QrImport {
  final String link;

  const QrImportServerLink(this.link);
}

/// A whole subscription in a `cattunnel://subscription?url=...` link.
final class QrImportSubscriptionLink extends QrImport {
  final SubscriptionData subscription;

  const QrImportSubscriptionLink(this.subscription);
}

/// A one-time subscription code that still has to be exchanged for a URL.
final class QrImportSubscriptionCode extends QrImport {
  final String code;
  final String base;

  const QrImportSubscriptionCode({required this.code, required this.base});
}
