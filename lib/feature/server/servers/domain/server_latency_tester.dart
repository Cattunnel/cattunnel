/// Address helpers shared by the connection checks. The app no longer measures
/// a server by connecting to its address: see ServerLatencyController.
class ServerLatencyTester {
  const ServerLatencyTester._();

  /// Splits a stored address into host/port, defaulting to port 443 when
  /// none is specified - matching how the app already treats addresses
  /// without an explicit port elsewhere (see the export/import link format).
  static (String, int) parseAddress(String address) {
    final trimmed = address.trim();

    // IPv6 literal with an explicit port: "[::1]:443".
    if (trimmed.startsWith('[')) {
      final closingBracket = trimmed.indexOf(']');
      if (closingBracket != -1) {
        final host = trimmed.substring(1, closingBracket);
        final rest = trimmed.substring(closingBracket + 1);
        final port = rest.startsWith(':') ? int.tryParse(rest.substring(1)) : null;

        return (host, port ?? 443);
      }
    }

    // Bare IPv6 literal has multiple colons and no explicit port here.
    if (trimmed.split(':').length > 2) {
      return (trimmed, 443);
    }

    final lastColon = trimmed.lastIndexOf(':');

    if (lastColon <= 0) {
      return (trimmed, 443);
    }

    final host = trimmed.substring(0, lastColon);
    final port = int.tryParse(trimmed.substring(lastColon + 1));

    return (host, port ?? 443);
  }
}
