import 'package:trusttunnel/data/datasources/subscription_datasource.dart';
import 'package:trusttunnel/data/domain/subscription_sync_service.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';

abstract class SubscriptionRepository {
  Future<List<SubscriptionData>> getAllSubscriptions();

  Future<SubscriptionData> addSubscription({required SubscriptionData request});

  Future<void> updateSubscription({required String id, required SubscriptionData request});

  Future<void> removeSubscription({required String id});

  /// Fetches [subscription]'s current server list and reconciles it into the
  /// database. Throws on a network/parse failure - the caller decides how to
  /// surface that.
  Future<void> refresh({required SubscriptionData subscription});
}

class SubscriptionRepositoryImpl implements SubscriptionRepository {
  final SubscriptionDataSource _dataSource;
  final SubscriptionSyncService _syncService;

  SubscriptionRepositoryImpl({
    required SubscriptionDataSource dataSource,
    required SubscriptionSyncService syncService,
  }) : _dataSource = dataSource,
       _syncService = syncService;

  @override
  Future<List<SubscriptionData>> getAllSubscriptions() => _dataSource.getAllSubscriptions();

  @override
  Future<SubscriptionData> addSubscription({required SubscriptionData request}) =>
      _dataSource.addSubscription(request: request);

  @override
  Future<void> updateSubscription({required String id, required SubscriptionData request}) =>
      _dataSource.updateSubscription(id: id, request: request);

  @override
  Future<void> removeSubscription({required String id}) => _dataSource.removeSubscription(id: id);

  @override
  Future<void> refresh({required SubscriptionData subscription}) => _syncService.refresh(subscription);
}
