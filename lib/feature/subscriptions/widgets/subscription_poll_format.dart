import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/subscription_poll.dart';

/// A short, locale-aware duration: `420 мс` under a second, `0,4 с` above it.
String subscriptionPollDuration(BuildContext context, int milliseconds) {
  final ln = context.ln;
  if (milliseconds < 1000) {
    return ln.subscriptionPollMilliseconds('$milliseconds');
  }

  final locale = Localizations.localeOf(context).toString();
  final seconds = NumberFormat('0.0', locale).format(milliseconds / 1000);

  return ln.subscriptionPollSeconds(seconds);
}

/// The result of one attempt, as the list under a subscription shows it.
String subscriptionPollOutcomeLabel(BuildContext context, SubscriptionPollAttempt attempt) {
  final ln = context.ln;

  return switch (attempt.outcome) {
    SubscriptionPollOutcome.ok => ln.subscriptionPollOk,
    SubscriptionPollOutcome.http => ln.subscriptionPollHttp(attempt.statusCode ?? ''),
    SubscriptionPollOutcome.timeout => ln.subscriptionPollTimeout,
    SubscriptionPollOutcome.noNetwork => ln.subscriptionPollNoNetwork,
    SubscriptionPollOutcome.tls => ln.subscriptionPollTls,
    SubscriptionPollOutcome.other => ln.subscriptionPollOther,
    SubscriptionPollOutcome.decrypt => ln.subscriptionPollDecrypt,
  };
}
