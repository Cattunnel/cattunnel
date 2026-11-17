import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/data/model/subscription_poll.dart';

/// Keeps the last mirror poll of every subscription: what was asked, in which
/// order, how long each mirror took and how it ended.
///
/// The record is kept in memory for the screen and in shared_preferences so it
/// survives a restart. Only `host[:port]` is stored - never the subscription
/// URL with its token, and never a key.
class SubscriptionPollLog extends ChangeNotifier {
  static const _keyPrefix = 'subscription_poll_';

  final SharedPreferences? _preferences;
  final Map<String, SubscriptionPoll> _polls = {};

  SubscriptionPollLog({SharedPreferences? preferences}) : _preferences = preferences {
    final stored = _preferences;
    if (stored == null) return;

    for (final key in stored.getKeys()) {
      if (!key.startsWith(_keyPrefix)) continue;
      final poll = SubscriptionPoll.tryParse(stored.getString(key));
      if (poll != null) {
        _polls[poll.subscriptionId] = poll;
      }
    }
  }

  SubscriptionPoll? pollOf(String? subscriptionId) {
    if (subscriptionId == null || subscriptionId.isEmpty) return null;

    return _polls[subscriptionId];
  }

  /// Starts a new poll, dropping the previous result of this subscription.
  void beginPoll({required String subscriptionId, required String subscriptionName}) {
    _polls[subscriptionId] = SubscriptionPoll(
      subscriptionId: subscriptionId,
      subscriptionName: subscriptionName,
      startedAt: DateTime.now(),
      attempts: const [],
    );
    notifyListeners();
  }

  /// The mirror being asked right now (shown while «Обновить» runs).
  void startAttempt(String subscriptionId, String host) {
    final poll = _polls[subscriptionId];
    if (poll == null) return;

    _polls[subscriptionId] = poll.copyWith(currentHost: host);
    notifyListeners();
  }

  void recordAttempt(String subscriptionId, SubscriptionPollAttempt attempt) {
    final poll = _polls[subscriptionId];
    if (poll == null) return;

    _polls[subscriptionId] = poll.copyWith(
      attempts: [...poll.attempts, attempt],
      clearCurrentHost: true,
    );
    notifyListeners();
  }

  /// The body arrived but could not be decrypted: the mirror that answered
  /// gets that as its outcome instead of a plain 200.
  void markDecryptionFailed(String subscriptionId) {
    final poll = _polls[subscriptionId];
    if (poll == null || poll.attempts.isEmpty) return;

    final attempts = [...poll.attempts];
    final last = attempts.last;
    attempts[attempts.length - 1] = SubscriptionPollAttempt(
      host: last.host,
      durationMs: last.durationMs,
      outcome: SubscriptionPollOutcome.decrypt,
      statusCode: last.statusCode,
    );
    _polls[subscriptionId] = poll.copyWith(attempts: attempts, clearCurrentHost: true);
    notifyListeners();
  }

  /// Ends the poll and persists it. A poll that was never started is ignored.
  Future<void> finishPoll(String subscriptionId, {required bool succeeded}) async {
    final poll = _polls[subscriptionId];
    if (poll == null) return;

    final finished = poll.copyWith(
      finishedAt: DateTime.now(),
      succeeded: succeeded,
      clearCurrentHost: true,
    );
    _polls[subscriptionId] = finished;
    notifyListeners();

    final preferences = _preferences;
    if (preferences == null) return;
    await preferences.setString('$_keyPrefix$subscriptionId', finished.toJsonString());
  }

  /// The same list as text for the exported logs: no tokens, no keys.
  List<String> toLogLines() {
    final lines = <String>[];
    for (final poll in _polls.values) {
      final finished = poll.finishedAt?.toIso8601String() ?? 'in progress';
      lines.add(
        '${poll.startedAt.toIso8601String()} ${poll.subscriptionName} '
        '${poll.succeeded ? 'OK' : 'FAILED'} ($finished)',
      );
      for (final attempt in poll.attempts) {
        lines.add(
          '  ${attempt.host} ${attempt.outcome.name} '
          '${attempt.statusCode ?? '-'} ${attempt.durationMs} ms',
        );
      }
    }

    return lines;
  }
}
