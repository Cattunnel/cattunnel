/// Cleans the engine's raw log lines before they go into an exported archive
/// (audit 13.10 item 5): credentials and subscription tokens never leave the
/// phone; IP addresses keep only their network part (`203.0.*.*`,
/// `2001:db8:*`) - enough to tell our servers and the operator apart, not to
/// pin a user. Domains stay: they are what a "this site doesn't open" report
/// is about, and the engine logs them only at the levels the user turns on.
abstract final class EngineLineScrubber {
  static final _secretKeys = RegExp(
    r'''\b(username|user|login|password|pass|client_random(?:_auth_key)?|auth_key|secret|token)(\s*[=:]\s*)("[^"]*"|'[^']*'|[^\s,;)\]]+)''',
    caseSensitive: false,
  );
  static final _subscriptionToken = RegExp(r'(/api/ct/)[A-Za-z0-9_\-]+');
  static final _ttLink = RegExp(r'tt://\??[A-Za-z0-9_\-=]+');
  static final _ipv4 = RegExp(r'\b(\d{1,3})\.(\d{1,3})\.\d{1,3}\.\d{1,3}\b');
  static final _ipv6 = RegExp(r'\b([0-9a-fA-F]{1,4}):([0-9a-fA-F]{1,4}):[0-9a-fA-F:]*[0-9a-fA-F]{1,4}\b');

  static String scrub(String line) => line
      .replaceAllMapped(_secretKeys, (m) => '${m[1]}${m[2]}***')
      .replaceAllMapped(_subscriptionToken, (m) => '${m[1]}***')
      .replaceAll(_ttLink, 'tt://***')
      .replaceAllMapped(_ipv4, (m) => '${m[1]}.${m[2]}.*.*')
      .replaceAllMapped(_ipv6, (m) => '${m[1]}:${m[2]}:*');
}
