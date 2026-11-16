import 'package:flutter/foundation.dart';
import 'package:trusttunnel/data/domain/subscription_sync_service.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/data/repository/subscription_repository.dart';

/// Exchanges a one-time subscription code for a URL and stores the
/// subscription.
///
/// Shared by the deep link handler and the QR scanner so a code from a
/// Telegram link, a `.cattunnel` file or a QR is imported exactly the same way.
Future<SubscriptionData> exchangeSubscriptionCode({
  required SubscriptionSyncService syncService,
  required SubscriptionRepository repository,
  required String code,
  required String base,
}) async {
  final subscription = await syncService.exchangeCode(code, base);
  final added = await repository.addSubscription(request: subscription);
  // Download the servers right away, as the manual add does
  // (subscriptions_screen.dart). Without it a subscription from a browser link
  // or a QR stayed empty until a manual refresh (S22, 16.11). A failed first
  // download keeps the subscription: the next refresh retries it.
  try {
    await repository.refresh(subscription: added);
  } on Object catch (e) {
    debugPrint('exchangeSubscriptionCode: first refresh failed: ${e.runtimeType}');
  }

  return added;
}
