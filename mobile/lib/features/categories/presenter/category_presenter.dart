import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';

class CategoryPresenter extends ActionPresenter {
  final CategoryRepository _repository;
  CategoryPresenter(this._repository);
  Future<bool> save(CategoryDraft draft, {String? id}) {
    final error = InputRules.name(draft.name);
    if (error != null) {
      emit(ActionState(error: error));
      return Future.value(false);
    }
    return perform(() => _repository.saveCategory(draft, id: id));
  }

  Future<bool> delete(String id) =>
      perform(() => _repository.deleteCategory(id));
}
