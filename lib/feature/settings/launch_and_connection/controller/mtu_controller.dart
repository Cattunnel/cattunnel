import 'package:trusttunnel/common/controller/concurrency/sequential_controller_handler.dart';
import 'package:trusttunnel/common/controller/controller/state_controller.dart';
import 'package:trusttunnel/common/error/exception_utils.dart';
import 'package:trusttunnel/data/repository/mtu_settings_repository.dart';
import 'package:trusttunnel/feature/settings/launch_and_connection/controller/mtu_state.dart';

/// Valid MTU range for the tunnel interface: below the IPv4 minimum
/// reassembly size doesn't make sense, above the standard Ethernet MTU isn't
/// meaningful for a tunnel carried over ordinary IP networks.
const mtuMinValue = 576;
const mtuMaxValue = 1500;

final class MtuController extends BaseStateController<MtuState> with SequentialControllerHandler {
  final MtuSettingsRepository _repository;

  MtuController({
    required MtuSettingsRepository repository,
    super.initialState = const MtuState.initial(),
  }) : _repository = repository;

  void fetch() => handle(
    () async {
      setState(MtuState.loading(value: state.value));

      final value = await _repository.getValue();

      setState(MtuState.idle(value: value));
    },
    errorHandler: _onError,
    completionHandler: _onCompleted,
  );

  void setValue(int mtu) => handle(
    () async {
      if (mtu < mtuMinValue || mtu > mtuMaxValue) {
        return;
      }

      setState(MtuState.loading(value: state.value));

      await _repository.setValue(mtu);

      setState(MtuState.idle(value: mtu));
    },
    errorHandler: _onError,
    completionHandler: _onCompleted,
  );

  void _onError(Object? error, StackTrace? stackTrace) => setState(
    MtuState.error(
      value: state.value,
      error: ExceptionUtils.toPresentationException(exception: error),
    ),
  );

  void _onCompleted() => setState(
    MtuState.idle(value: state.value),
  );
}
