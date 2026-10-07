import 'package:trusttunnel/common/error/model/presentation_exception.dart';

sealed class MtuState {
  final int value;

  const MtuState({
    required this.value,
  });

  const factory MtuState.initial() = _MtuInitialState;

  const factory MtuState.idle({
    required int value,
  }) = _MtuIdleState;

  const factory MtuState.loading({
    required int value,
  }) = _MtuLoadingState;

  const factory MtuState.error({
    required int value,
    required PresentationException error,
  }) = _MtuErrorState;

  PresentationException? get error => switch (this) {
    _MtuErrorState(:final error) => error,
    _ => null,
  };

  bool get loading => this is _MtuLoadingState;

  @override
  int get hashCode => Object.hash(
    value,
    error,
    loading,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MtuState &&
          runtimeType == other.runtimeType &&
          value == other.value &&
          error == other.error &&
          loading == other.loading;

  @override
  String toString() => 'MtuState(type: $runtimeType, value: $value, loading: $loading)';
}

final class _MtuInitialState extends _MtuIdleState {
  const _MtuInitialState() : super(value: 1500);
}

final class _MtuIdleState extends MtuState {
  const _MtuIdleState({
    required super.value,
  });
}

final class _MtuLoadingState extends MtuState {
  const _MtuLoadingState({
    required super.value,
  });
}

final class _MtuErrorState extends MtuState {
  @override
  final PresentationException error;

  const _MtuErrorState({
    required super.value,
    required this.error,
  });
}
