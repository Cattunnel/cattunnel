import 'package:trusttunnel/common/controller/concurrency/sequential_controller_handler.dart';
import 'package:trusttunnel/common/controller/controller/state_controller.dart';
import 'package:trusttunnel/common/error/exception_utils.dart';
import 'package:trusttunnel/data/repository/kill_switch_settings_repository.dart';
import 'package:trusttunnel/feature/settings/launch_and_connection/controller/kill_switch_state.dart';

final class KillSwitchController extends BaseStateController<KillSwitchState> with SequentialControllerHandler {
  final KillSwitchSettingsRepository _repository;

  KillSwitchController({
    required KillSwitchSettingsRepository repository,
    super.initialState = const KillSwitchState.initial(),
  }) : _repository = repository;

  void fetch() => handle(
    () async {
      setState(
        KillSwitchState.loading(
          enabled: state.enabled,
        ),
      );

      final enabled = await _repository.isEnabled();

      setState(
        KillSwitchState.idle(
          enabled: enabled,
        ),
      );
    },
    errorHandler: _onError,
    completionHandler: _onCompleted,
  );

  void enable() => _applyEnabled(enabled: true);

  void disable() => _applyEnabled(enabled: false);

  void _applyEnabled({required bool enabled}) => handle(
    () async {
      setState(
        KillSwitchState.loading(
          enabled: state.enabled,
        ),
      );

      if (enabled) {
        await _repository.enable();
      } else {
        await _repository.disable();
      }
      final actualEnabled = await _repository.isEnabled();

      setState(
        KillSwitchState.idle(
          enabled: actualEnabled,
        ),
      );
    },
    errorHandler: _onError,
    completionHandler: _onCompleted,
  );

  void _onError(Object? error, StackTrace? stackTrace) => setState(
    KillSwitchState.error(
      enabled: state.enabled,
      error: ExceptionUtils.toPresentationException(exception: error),
    ),
  );

  void _onCompleted() => setState(
    KillSwitchState.idle(
      enabled: state.enabled,
    ),
  );
}
