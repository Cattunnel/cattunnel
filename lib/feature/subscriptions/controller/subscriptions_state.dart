import 'package:collection/collection.dart';
import 'package:trusttunnel/common/error/model/presentation_exception.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';

sealed class SubscriptionsState {
  final List<SubscriptionData> subscriptions;

  /// Ids of subscriptions currently being refreshed.
  final Set<String> refreshingIds;

  const SubscriptionsState._({
    required this.subscriptions,
    required this.refreshingIds,
  });

  const factory SubscriptionsState.initial() = _InitialSubscriptionsState;

  const factory SubscriptionsState.idle({
    required List<SubscriptionData> subscriptions,
    required Set<String> refreshingIds,
  }) = _IdleSubscriptionsState;

  const factory SubscriptionsState.loading({
    required List<SubscriptionData> subscriptions,
    required Set<String> refreshingIds,
  }) = _LoadingSubscriptionsState;

  const factory SubscriptionsState.error({
    required List<SubscriptionData> subscriptions,
    required Set<String> refreshingIds,
    required PresentationException exception,
  }) = _ErrorSubscriptionsState;

  PresentationException? get error => this is _ErrorSubscriptionsState ? (this as _ErrorSubscriptionsState).exception : null;

  bool get loading => this is _LoadingSubscriptionsState;

  @override
  int get hashCode => Object.hash(
    runtimeType,
    Object.hashAll(subscriptions),
    Object.hashAll(refreshingIds),
    error,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionsState &&
          runtimeType == other.runtimeType &&
          const ListEquality<SubscriptionData>().equals(subscriptions, other.subscriptions) &&
          const SetEquality<String>().equals(refreshingIds, other.refreshingIds) &&
          error == other.error;

  @override
  String toString() =>
      'SubscriptionsState(type: $runtimeType, subscriptions: $subscriptions, refreshingIds: $refreshingIds, loading: $loading)';
}

final class _IdleSubscriptionsState extends SubscriptionsState {
  const _IdleSubscriptionsState({
    required super.subscriptions,
    required super.refreshingIds,
  }) : super._();
}

final class _InitialSubscriptionsState extends _IdleSubscriptionsState {
  const _InitialSubscriptionsState() : super(subscriptions: const [], refreshingIds: const {});
}

final class _LoadingSubscriptionsState extends SubscriptionsState {
  const _LoadingSubscriptionsState({
    required super.subscriptions,
    required super.refreshingIds,
  }) : super._();
}

final class _ErrorSubscriptionsState extends SubscriptionsState {
  final PresentationException exception;

  const _ErrorSubscriptionsState({
    required super.subscriptions,
    required super.refreshingIds,
    required this.exception,
  }) : super._();
}
