import 'dart:async';

/// Plain Dart presentation lifecycle. Widgets only subscribe to [states].
abstract class Presenter<S> {
  S _state;
  Presenter(this._state);
  final _states = StreamController<S>.broadcast(sync: true);
  final _effects = StreamController<PresentationEffect>.broadcast(sync: true);
  bool _disposed = false;
  S get state => _state;
  Stream<S> get states => _states.stream;
  Stream<PresentationEffect> get effects => _effects.stream;
  bool get disposed => _disposed;
  void emit(S state) {
    if (_disposed) return;
    _state = state;
    _states.add(state);
  }

  void effect(PresentationEffect effect) {
    if (!_disposed) _effects.add(effect);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _states.close();
    _effects.close();
  }
}

sealed class PresentationEffect {
  const PresentationEffect();
}

class DataChanged extends PresentationEffect {
  final DateTime? month;
  const DataChanged({this.month});
}

class ActionState {
  final bool busy;
  final String? error;
  const ActionState({this.busy = false, this.error});
}

abstract class ActionPresenter extends Presenter<ActionState> {
  ActionPresenter() : super(const ActionState());
  Future<bool> perform(
    Future<void> Function() operation, {
    DateTime? month,
  }) async {
    if (state.busy || disposed) return false;
    emit(const ActionState(busy: true));
    try {
      await operation();
      if (disposed) return false;
      emit(const ActionState());
      effect(DataChanged(month: month));
      return true;
    } catch (error) {
      emit(ActionState(error: error.toString()));
      return false;
    }
  }
}
