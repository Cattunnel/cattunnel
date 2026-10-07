/// Normalizes raw `tt://` link text (typed, pasted, or scanned from a QR
/// code) into the exact URI shape the deep-link decode pipeline expects.
///
/// Mirrors the normalization already applied to OS-intent links in
/// `DeepLinkController.onDeepLinkReceived`.
abstract final class DeepLinkUriNormalizer {
  static const scheme = 'tt';

  /// Returns the normalized `tt://?<query>` string, or `null` if [input] is
  /// not a `tt://` link with a query payload.
  static String? normalize(String input) {
    final uri = Uri.tryParse(input.trim());

    if (uri == null || uri.scheme != scheme || !uri.hasQuery) {
      return null;
    }

    return Uri(scheme: scheme, host: '', query: uri.query).toString();
  }
}
