import 'package:flutter/foundation.dart';

/// {@template subscription_data}
/// A remote subscription: a URL that returns newline-separated `tt://`
/// server links, refreshed periodically to keep a group of servers in sync.
/// {@endtemplate}
@immutable
class SubscriptionData {
  final String? id;
  final String name;
  final String url;

  /// Whether TLS certificate verification is skipped when fetching [url].
  ///
  /// Scoped to this subscription's own HTTP client only - does not weaken
  /// TLS verification for any other subscription or the VPN connection
  /// itself.
  final bool skipVerification;

  final DateTime? lastUpdatedAt;

  final bool autoRefreshEnabled;

  /// An age (age-encryption.org/v1) X25519 identity (`AGE-SECRET-KEY-1...`).
  ///
  /// When set, the fetched [url] response is treated as an age-encrypted
  /// binary payload and decrypted with this identity before being parsed as
  /// `tt://` links - protects the subscription's server list from a passive
  /// network observer or active DPI probe of the subscription URL.
  final String? agePrivateKey;

  /// Separator between mirror URLs inside [url].
  static const mirrorSeparator = ' | ';

  /// Mirror URLs of this subscription, in the order they are tried.
  ///
  /// [url] may hold several URLs of the same subscription ("a | b"): when
  /// the first one is unreachable (e.g. its port got blocked) the next is
  /// tried. Always in this fixed order - the working mirror is deliberately
  /// not remembered, so the first URL stays the primary one. A plain single
  /// URL is simply a list of one; no database migration needed.
  List<String> get urls => splitUrls(url);

  /// Splits a "a | b" (or newline/space separated) mirror list.
  static List<String> splitUrls(String raw) =>
      raw.split(RegExp(r'[|\s]+')).map((part) => part.trim()).where((part) => part.isNotEmpty).toList();

  static String joinUrls(List<String> urls) => urls.join(mirrorSeparator);

  const SubscriptionData({
    required this.name,
    required this.url,
    this.id,
    this.skipVerification = false,
    this.lastUpdatedAt,
    this.autoRefreshEnabled = true,
    this.agePrivateKey,
  });

  SubscriptionData copyWith({
    String? name,
    String? url,
    bool? skipVerification,
    DateTime? lastUpdatedAt,
    bool? autoRefreshEnabled,
    ValueGetter<String?>? agePrivateKey,
  }) => SubscriptionData(
    id: id,
    name: name ?? this.name,
    url: url ?? this.url,
    skipVerification: skipVerification ?? this.skipVerification,
    lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    autoRefreshEnabled: autoRefreshEnabled ?? this.autoRefreshEnabled,
    agePrivateKey: agePrivateKey != null ? agePrivateKey() : this.agePrivateKey,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionData &&
          other.id == id &&
          other.name == name &&
          other.url == url &&
          other.skipVerification == skipVerification &&
          other.lastUpdatedAt == lastUpdatedAt &&
          other.autoRefreshEnabled == autoRefreshEnabled &&
          other.agePrivateKey == agePrivateKey;

  @override
  int get hashCode =>
      Object.hash(id, name, url, skipVerification, lastUpdatedAt, autoRefreshEnabled, agePrivateKey);

  @override
  /// The URL itself is a bearer secret (e.g. `/api/ct/<token>`), and this
  /// ends up in exportable logs via controller state dumps - host only.
  String toString() =>
      'SubscriptionData(id: $id, name: $name, '
      'url: ${urls.map((u) => '${Uri.tryParse(u)?.host ?? '<invalid>'}/<redacted>').join(mirrorSeparator)}, '
      'skipVerification: $skipVerification, '
      'lastUpdatedAt: $lastUpdatedAt, autoRefreshEnabled: $autoRefreshEnabled, '
      'agePrivateKey: ${agePrivateKey == null ? null : '<redacted>'})';
}
