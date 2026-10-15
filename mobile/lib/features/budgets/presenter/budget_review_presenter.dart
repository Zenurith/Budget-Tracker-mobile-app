import '../../../models/finance.dart';
import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';
import '../model/budget_review_repository.dart';

class BudgetReviewState {
  final Json? data;
  final bool busy;
  final String? error;
  const BudgetReviewState({this.data, this.busy = false, this.error});
}

class BudgetReviewPresenter extends Presenter<BudgetReviewState> {
  final BudgetReviewRepository repository;
  final bool Function() syncBlocked;
  final DateTime Function() now;
  BudgetReviewTarget? target;
  String? _owner;
  int _generation = 0;
  BudgetReviewPresenter(
    this.repository, {
    bool Function()? syncBlocked,
    DateTime Function()? now,
  }) : syncBlocked = syncBlocked ?? (() => false),
       now = now ?? DateTime.now,
       super(const BudgetReviewState());
  void setAccount(Account? account) {
    if (_owner == account?.id) return;
    _owner = account?.id;
    target = null;
    invalidate();
  }

  void invalidate() {
    ++_generation;
    emit(const BudgetReviewState());
  }

  bool get usable {
    final expiry = DateTime.tryParse('${state.data?['expires_at']}');
    return state.data != null &&
        !state.busy &&
        !syncBlocked() &&
        expiry != null &&
        now().isBefore(expiry);
  }

  Future<void> open(BudgetReviewTarget value) async {
    target = value;
    await refresh();
  }

  Future<void> refresh() async {
    final selected = target;
    if (disposed || selected == null || selected.ownerId != _owner) return;
    final generation = ++_generation;
    emit(const BudgetReviewState(busy: true));
    if (syncBlocked()) {
      emit(
        const BudgetReviewState(
          error: 'Sync pending spending changes before reviewing this budget.',
        ),
      );
      return;
    }
    try {
      final data = await repository.load(selected.period);
      if (disposed || generation != _generation) return;
      if (data['owner_id'] != _owner || data['period'] != selected.period) {
        throw StateError('Account changed');
      }
      if (syncBlocked()) throw StateError('Sync pending changes and retry.');
      emit(BudgetReviewState(data: freezeJson(data)));
    } catch (_) {
      if (!disposed && generation == _generation) {
        emit(
          const BudgetReviewState(
            error:
                'Could not load a fresh budget review. Connect, sync and retry.',
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }
}
