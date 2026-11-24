import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/server_group_settings.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';

abstract class SubscriptionDataSource {
  Future<List<SubscriptionData>> getAllSubscriptions();

  Future<SubscriptionData> addSubscription({required SubscriptionData request});

  Future<void> updateSubscription({required String id, required SubscriptionData request});

  /// Removes the subscription and every server row it owns.
  Future<void> removeSubscription({required String id});

  /// Reconciles the servers owned by subscription [id] with [servers], the
  /// freshly-fetched list.
  ///
  /// Matches by server name (unique within one subscription's own rows):
  /// existing rows are updated in place, new names are inserted, and rows
  /// whose name disappeared are deleted - unless they are the currently
  /// selected server, which is left alone so an in-progress connection is
  /// never disrupted by a background refresh.
  ///
  /// Never touches servers added manually or owned by a different
  /// subscription.
  Future<void> syncServersForSubscription({
    required String id,
    required List<ServerData> servers,
  });

  Future<void> markRefreshed({required String id, required DateTime at});

  /// The user's labels and order of the servers-screen groups, by group key.
  Future<Map<String, ServerGroupSettings>> getGroupSettings();

  /// Own display label of a group; empty restores the original name. Only a
  /// label: servers stay matched to their subscription by its real name.
  Future<void> setGroupLabel({required String key, required String label});

  /// Saves the order of all groups, first to last.
  Future<void> setGroupOrder({required List<String> keys});
}
