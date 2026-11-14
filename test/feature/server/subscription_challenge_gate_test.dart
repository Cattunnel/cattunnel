import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/subscription_override_dialog.dart';

// Owner 14.11: switching the bypass inside a subscription key asks the
// question first; once answered, the key is above the subscription and
// its bypass no longer resets (not at midnight, not on sync).
void main() {
  test('a subscription key asks before a manual change, a key above it does not', () {
    const own = ServerData.empty();
    const fromSubscription = ServerData.empty(subscriptionId: 'sub-1');
    expect(SubscriptionChallenge.needsChallenge(own), isFalse);
    expect(SubscriptionChallenge.needsChallenge(fromSubscription), isTrue);
    expect(SubscriptionChallenge.needsChallenge(fromSubscription.copyWith(subscriptionOverride: true)), isFalse);
  });
}
