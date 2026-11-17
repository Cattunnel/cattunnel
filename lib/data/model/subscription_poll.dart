import 'dart:convert';

import 'package:flutter/foundation.dart';

/// What one mirror of a subscription answered.
enum SubscriptionPollOutcome {
  /// The mirror returned the body (HTTP 200).
  ok,

  /// The mirror answered with a non-200 status.
  http,

  /// No answer within the mirror's connect timeout.
  timeout,

  /// The request never left the device (or the connection was closed).
  noNetwork,

  /// TLS could not be negotiated (TSPU cutting the ClientHello, a bad pin).
  tls,

  /// Anything else: a redirect, a wrong scheme, a broken response.
  other,

  /// The body arrived but could not be decrypted with the device's key.
  decrypt,
}

/// One attempt against one mirror.
///
/// [host] is `host` or `host:port` only: the subscription URL's path carries
/// the token, and this record is shown and exported, so the path and query
/// never get here.
@immutable
class SubscriptionPollAttempt {
  final String host;
  final int durationMs;
  final SubscriptionPollOutcome outcome;

  /// The HTTP status, when the mirror actually replied.
  final int? statusCode;

  const SubscriptionPollAttempt({
    required this.host,
    required this.durationMs,
    required this.outcome,
    this.statusCode,
  });

  bool get succeeded => outcome == SubscriptionPollOutcome.ok;

  Map<String, Object?> toJson() => {
    'host': host,
    'durationMs': durationMs,
    'outcome': outcome.name,
    if (statusCode != null) 'statusCode': statusCode,
  };

  static SubscriptionPollAttempt? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final host = raw['host'];
    final durationMs = raw['durationMs'];
    final outcome = raw['outcome'];
    if (host is! String || host.isEmpty || durationMs is! int || outcome is! String) return null;
    final statusCode = raw['statusCode'];

    return SubscriptionPollAttempt(
      host: host,
      durationMs: durationMs,
      outcome: SubscriptionPollOutcome.values.firstWhere(
        (value) => value.name == outcome,
        orElse: () => SubscriptionPollOutcome.other,
      ),
      statusCode: statusCode is int ? statusCode : null,
    );
  }

  @override
  String toString() => 'SubscriptionPollAttempt(host: $host, durationMs: $durationMs, outcome: $outcome)';
}

/// The last poll of one subscription: the mirrors that were asked, in order,
/// and how it ended. Stored in memory and in shared_preferences, never with
/// tokens or keys.
@immutable
class SubscriptionPoll {
  final String subscriptionId;
  final String subscriptionName;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final bool succeeded;
  final List<SubscriptionPollAttempt> attempts;

  /// The mirror being asked right now, while the poll is running.
  final String? currentHost;

  const SubscriptionPoll({
    required this.subscriptionId,
    required this.subscriptionName,
    required this.startedAt,
    required this.attempts,
    this.finishedAt,
    this.succeeded = false,
    this.currentHost,
  });

  bool get inProgress => finishedAt == null;

  SubscriptionPollAttempt? get lastSucceededAttempt {
    for (final attempt in attempts.reversed) {
      if (attempt.succeeded) return attempt;
    }

    return null;
  }

  SubscriptionPoll copyWith({
    DateTime? finishedAt,
    bool? succeeded,
    List<SubscriptionPollAttempt>? attempts,
    String? currentHost,
    bool clearCurrentHost = false,
  }) => SubscriptionPoll(
    subscriptionId: subscriptionId,
    subscriptionName: subscriptionName,
    startedAt: startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    succeeded: succeeded ?? this.succeeded,
    attempts: attempts ?? this.attempts,
    currentHost: clearCurrentHost ? null : (currentHost ?? this.currentHost),
  );

  Map<String, Object?> toJson() => {
    'subscriptionId': subscriptionId,
    'subscriptionName': subscriptionName,
    'startedAt': startedAt.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'succeeded': succeeded,
    'attempts': attempts.map((attempt) => attempt.toJson()).toList(),
  };

  String toJsonString() => jsonEncode(toJson());

  static SubscriptionPoll? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final id = data['subscriptionId'];
      final startedAt = DateTime.tryParse('${data['startedAt'] ?? ''}');
      final attempts = data['attempts'];
      if (id is! String || id.isEmpty || startedAt == null || attempts is! List) return null;

      return SubscriptionPoll(
        subscriptionId: id,
        subscriptionName: '${data['subscriptionName'] ?? ''}',
        startedAt: startedAt,
        finishedAt: DateTime.tryParse('${data['finishedAt'] ?? ''}'),
        succeeded: data['succeeded'] == true,
        attempts: [
          for (final rawAttempt in attempts)
            if (SubscriptionPollAttempt.tryParse(rawAttempt) case final attempt?) attempt,
        ],
      );
    } on Object {
      // A broken or older record: no poll is better than a crash on startup.
      return null;
    }
  }

  /// `host` or `host:port` of [url] - the path (the subscription token) and
  /// the query are never part of it.
  static String hostOf(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    if (host.isEmpty) return '<invalid>';
    final printable = host.contains(':') ? '[$host]' : host;

    return uri!.hasPort ? '$printable:${uri.port}' : printable;
  }

  @override
  String toString() =>
      'SubscriptionPoll(subscription: $subscriptionId, startedAt: $startedAt, succeeded: $succeeded, attempts: $attempts)';
}
