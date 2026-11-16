import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/domain/subscription_code_exchange.dart';
import 'package:trusttunnel/data/domain/subscription_sync_service.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/data/repository/subscription_repository.dart';

// 16.11: a subscription added from a browser link or a QR code was saved but
// never downloaded (S22: POST /api/ct/exchange 200, no GET /api/ct/... after).
// The manual add refreshes right away (subscriptions_screen.dart, refresh(added)).

class _FakeSync implements SubscriptionSyncService {
  @override
  Future<SubscriptionData> exchangeCode(String code, String base) async =>
      const SubscriptionData(name: 'CatTunnel', url: 'https://a.example/api/ct/t');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRepository implements SubscriptionRepository {
  final refreshed = <SubscriptionData>[];
  Object? refreshError;

  @override
  Future<SubscriptionData> addSubscription({required SubscriptionData request}) async =>
      SubscriptionData(id: 's1', name: request.name, url: request.url);

  @override
  Future<void> refresh({required SubscriptionData subscription}) async {
    refreshed.add(subscription);
    if (refreshError case final error?) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a subscription from a one-time code is downloaded right after it is added', () async {
    final repository = _FakeRepository();
    final added = await exchangeSubscriptionCode(
      syncService: _FakeSync(),
      repository: repository,
      code: 'c',
      base: 'https://a.example',
    );

    expect(added.id, 's1');
    expect(repository.refreshed.map((s) => s.id), ['s1']);
  });

  test('a failed first download keeps the added subscription', () async {
    final repository = _FakeRepository()..refreshError = const SubscriptionFetchException('offline');
    final added = await exchangeSubscriptionCode(
      syncService: _FakeSync(),
      repository: repository,
      code: 'c',
      base: 'https://a.example',
    );

    expect(added.id, 's1');
    expect(repository.refreshed, hasLength(1));
  });
}
