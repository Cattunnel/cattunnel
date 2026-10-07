import 'package:trusttunnel/common/controller/concurrency/sequential_controller_handler.dart';
import 'package:trusttunnel/common/controller/controller/state_controller.dart';
import 'package:trusttunnel/common/error/exception_utils.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/data/repository/subscription_repository.dart';
import 'package:trusttunnel/feature/subscriptions/controller/subscriptions_state.dart';

final class SubscriptionsController extends BaseStateController<SubscriptionsState> with SequentialControllerHandler {
  final SubscriptionRepository _repository;

  SubscriptionsController({
    required SubscriptionRepository repository,
    super.initialState = const SubscriptionsState.initial(),
  }) : _repository = repository;

  Future<void> fetch() => handle(
    () async {
      setState(
        SubscriptionsState.loading(
          subscriptions: state.subscriptions,
          refreshingIds: state.refreshingIds,
        ),
      );

      final subscriptions = await _repository.getAllSubscriptions();

      setState(
        SubscriptionsState.idle(
          subscriptions: subscriptions,
          refreshingIds: state.refreshingIds,
        ),
      );
    },
    errorHandler: _onError,
    completionHandler: _onCompleted,
  );

  Future<void> add(SubscriptionData request) => handle(
    () async {
      await _repository.addSubscription(request: request);
      final subscriptions = await _repository.getAllSubscriptions();

      setState(
        SubscriptionsState.idle(
          subscriptions: subscriptions,
          refreshingIds: state.refreshingIds,
        ),
      );
    },
    errorHandler: _onError,
    completionHandler: _onCompleted,
  );

  Future<void> update(String id, SubscriptionData request) => handle(
    () async {
      await _repository.updateSubscription(id: id, request: request);
      final subscriptions = await _repository.getAllSubscriptions();

      setState(
        SubscriptionsState.idle(
          subscriptions: subscriptions,
          refreshingIds: state.refreshingIds,
        ),
      );
    },
    errorHandler: _onError,
    completionHandler: _onCompleted,
  );

  Future<void> remove(String id) => handle(
    () async {
      await _repository.removeSubscription(id: id);
      final subscriptions = state.subscriptions.where((s) => s.id != id).toList();

      setState(
        SubscriptionsState.idle(
          subscriptions: subscriptions,
          refreshingIds: state.refreshingIds,
        ),
      );
    },
    errorHandler: _onError,
    completionHandler: _onCompleted,
  );

  /// Refreshes one subscription's server list. Tracked independently of the
  /// controller's sequential [handle] queue so refreshing one subscription
  /// doesn't block interacting with the rest of the screen.
  Future<void> refresh(SubscriptionData subscription) async {
    final id = subscription.id;
    if (id == null || state.refreshingIds.contains(id)) {
      return;
    }

    setState(
      SubscriptionsState.idle(
        subscriptions: state.subscriptions,
        refreshingIds: {...state.refreshingIds, id},
      ),
    );

    try {
      await _repository.refresh(subscription: subscription);
      final subscriptions = await _repository.getAllSubscriptions();

      setState(
        SubscriptionsState.idle(
          subscriptions: subscriptions,
          refreshingIds: state.refreshingIds.where((e) => e != id).toSet(),
        ),
      );
    } catch (error) {
      setState(
        SubscriptionsState.error(
          subscriptions: state.subscriptions,
          refreshingIds: state.refreshingIds.where((e) => e != id).toSet(),
          exception: ExceptionUtils.toPresentationException(exception: error),
        ),
      );
    }
  }

  Future<void> _onError(Object? error, StackTrace _) async => setState(
    SubscriptionsState.error(
      subscriptions: state.subscriptions,
      refreshingIds: state.refreshingIds,
      exception: ExceptionUtils.toPresentationException(exception: error),
    ),
  );

  Future<void> _onCompleted() async => setState(
    SubscriptionsState.idle(
      subscriptions: state.subscriptions,
      refreshingIds: state.refreshingIds,
    ),
  );
}
