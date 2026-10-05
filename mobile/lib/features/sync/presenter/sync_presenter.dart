import 'dart:async';
import '../../../core/presentation/presenter.dart';
import '../model/sync_repository.dart';

class SyncPresenter extends Presenter<SyncState> {
  final SyncRepository repository;
  late final StreamSubscription<SyncState> _subscription;
  SyncPresenter(this.repository) : super(repository.state) {
    _subscription = repository.states.listen(emit);
  }
  Future<void> run(Future<void> Function() action) async {
    if (disposed || state.busy) return;
    emit(
      SyncState(
        operations: state.operations,
        offline: state.offline,
        busy: true,
      ),
    );
    try {
      await action();
      emit(repository.state);
      if (!disposed) effect(const DataChanged());
    } catch (e) {
      emit(
        SyncState(
          operations: repository.state.operations,
          offline: repository.state.offline,
          error: e.toString(),
        ),
      );
    }
  }

  Future<void> synchronize() => run(repository.synchronize);
  Future<void> review(String id) => run(() => repository.review(id));
  Future<void> resolve(String id, {required bool useLocal}) =>
      run(() => repository.resolve(id, useLocal: useLocal));
  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
