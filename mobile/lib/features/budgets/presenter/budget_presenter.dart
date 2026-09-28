import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';

class BudgetPresenter extends ActionPresenter {
  final BudgetRepository _repository;
  BudgetPresenter(this._repository);
  String? validateAmount(String? value) => InputRules.amount(value);
  String? validateThreshold(String? value) => InputRules.threshold(value);
  Future<bool> save(BudgetDraft draft) {
    if (draft.limitAmount <= 0 ||
        draft.limitAmount > 100000000000 ||
        draft.alertThreshold < 1 ||
        draft.alertThreshold > 100) {
      emit(
        const ActionState(
          error: 'Enter a positive limit and a threshold from 1 to 100.',
        ),
      );
      return Future.value(false);
    }
    return perform(() => _repository.saveBudget(draft));
  }

  Future<bool> delete(String id) => perform(() => _repository.deleteBudget(id));
}
