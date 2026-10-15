import 'dart:convert';
import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';
import '../../budgets/model/budget_review_repository.dart';

class NotificationNavigationPresenter extends Presenter<BudgetReviewTarget?> {
  Account? _account;
  BudgetReviewTarget? _pending;
  NotificationNavigationPresenter() : super(null);
  void open(String? payload) {
    if (disposed || payload == null || payload.length > 100000) return;
    try {
      final data = jsonDecode(payload);
      if (data is! Map ||
          data['type'] != 'budget_review_v1' ||
          data['owner'] is! String ||
          (data['owner'] as String).isEmpty ||
          data['period'] is! String ||
          !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(data['period']) ||
          data['ids'] is! List ||
          (data['ids'] as List).isEmpty ||
          (data['ids'] as List).length > 1000 ||
          (data['ids'] as List).any(
            (id) => id is! String || id.isEmpty || id.length > 128,
          )) {
        return;
      }
      _pending = BudgetReviewTarget(
        data['owner'],
        data['period'],
        (data['ids'] as List).cast<String>(),
      );
      _publish();
    } catch (_) {
      /* Unknown/old notification payloads open the app normally. */
    }
  }

  void setAccount(Account? account) {
    if (_account?.id != account?.id) emit(null);
    _account = account;
    _publish();
  }

  void _publish() {
    if (_account == null || _pending == null) return;
    final target = _pending!;
    _pending = null;
    if (target.ownerId == _account!.id) emit(target);
  }

  void consume() {
    if (state != null) emit(null);
  }

  void clear() {
    _pending = null;
    _account = null;
    consume();
  }
}
