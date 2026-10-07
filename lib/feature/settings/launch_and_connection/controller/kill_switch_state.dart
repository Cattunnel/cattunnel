import 'package:trusttunnel/common/error/model/presentation_exception.dart';

sealed class KillSwitchState {
  final bool enabled;

  const KillSwitchState({
    required this.enabled,
  });

  const factory KillSwitchState.initial() = _KillSwitchInitialState;

  const factory KillSwitchState.idle({
    required bool enabled,
  }) = _KillSwitchIdleState;

  const factory KillSwitchState.loading({
    required bool enabled,
  }) = _KillSwitchLoadingState;

  const factory KillSwitchState.error({
    required bool enabled,
    required PresentationException error,
  }) = _KillSwitchErrorState;

  PresentationException? get error => switch (this) {
    _KillSwitchErrorState(:final error) => error,
    _ => null,
  };

  bool get loading => this is _KillSwitchLoadingState;

  @override
  int get hashCode => Object.hash(
    enabled,
    error,
    loading,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KillSwitchState &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          error == other.error &&
          loading == other.loading;

  @override
  String toString() => 'KillSwitchState(type: $runtimeType, enabled: $enabled, loading: $loading)';
}

final class _KillSwitchInitialState extends _KillSwitchIdleState {
  const _KillSwitchInitialState() : super(enabled: true);
}

final class _KillSwitchIdleState extends KillSwitchState {
  const _KillSwitchIdleState({
    required super.enabled,
  });
}

final class _KillSwitchLoadingState extends KillSwitchState {
  const _KillSwitchLoadingState({
    required super.enabled,
  });
}

final class _KillSwitchErrorState extends KillSwitchState {
  @override
  final PresentationException error;

  const _KillSwitchErrorState({
    required super.enabled,
    required this.error,
  });
}
