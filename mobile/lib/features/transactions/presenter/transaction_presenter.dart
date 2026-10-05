import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';

class TransactionPresenter extends ActionPresenter {
  final TransactionRepository _repository;
  TransactionPresenter(this._repository);
  String? validateAmount(String? value) => InputRules.amount(value);
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
    if (draft.amount <= 0 ||
        draft.amount > 100000000000 ||
        draft.categoryId.isEmpty) {
      emit(
        const ActionState(
          error: 'Enter a positive amount and choose a category.',
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
