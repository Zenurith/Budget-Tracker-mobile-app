import '../model/transaction_input_rules.dart';
import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';

class TransactionPresenter extends ActionPresenter {
  final TransactionRepository _repository;
  TransactionPresenter(this._repository);
  String? validateAmount(String? value) => TransactionInputRules.amount(value);
  Future<ParsedEntry?> parse(String text, DateTime referenceDate) async {
    if (state.busy || disposed) return null;
    if (text.trim().isEmpty) {
      emit(const ActionState(error: 'Tell us what you spent or received.'));
      return null;
    }
    emit(const ActionState(busy: true));
    try {
      final result = await _repository.parse(text, referenceDate);
      emit(const ActionState());
      return disposed ? null : result;
    } catch (error) {
      emit(ActionState(error: error.toString()));
      return null;
    }
  }

  Future<bool> save(EntryDraft draft, {String? id}) {
    if (state.busy || disposed) return Future.value(false);
    final error = draft.amount <= 0
        ? 'Enter an amount greater than zero'
        : draft.amount > 100000000000
        ? 'Amount must be 1,000,000,000.00 or less'
        : draft.categoryId.isEmpty
        ? 'Choose a category'
        : TransactionInputRules.note(draft.note);
    if (error != null) {
      emit(ActionState(error: error));
      return Future.value(false);
    }
    if (draft.splits.isNotEmpty &&
        (draft.splits.length < 2 ||
            draft.splits.length > 20 ||
            draft.splits.any((s) => s.amount <= 0 || s.categoryId.isEmpty) ||
            draft.splits.map((s) => s.categoryId).toSet().length !=
                draft.splits.length ||
            draft.splits.fold<int>(0, (sum, s) => sum + s.amount) !=
                draft.amount ||
            draft.splits.first.categoryId != draft.categoryId)) {
      emit(
        const ActionState(
          error:
              'Choose distinct categories and make split amounts equal the total.',
        ),
      );
      return Future.value(false);
    }
    return perform(
      () => _repository.saveEntry(draft, id: id),
      month: draft.date,
    );
  }

  Future<bool> delete(String id, {String? expectedVersion}) => perform(
    () => _repository.deleteEntry(id, expectedVersion: expectedVersion),
  );
}
