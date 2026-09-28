import 'dart:async';

import '../model/contracts.dart';
import 'presenter.dart';
import '../../features/auth/presenter/auth_presenter.dart';
import '../../features/overview/presenter/overview_presenter.dart';
import '../../features/transactions/presenter/transaction_presenter.dart';
import '../../features/budgets/presenter/budget_presenter.dart';
import '../../features/categories/presenter/category_presenter.dart';

/// Presentation composition: relays typed effects, never exposes data adapters.
class AppPresenters {
  final AuthPresenter auth;
  final OverviewPresenter overview;
  final TransactionPresenter transactions;
  final BudgetPresenter budgets;
  final CategoryPresenter categories;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  String? _accountId;
  AppPresenters({
    required AuthRepository authRepository,
    required OverviewRepository overviewRepository,
    required TransactionRepository transactionRepository,
    required BudgetRepository budgetRepository,
    required CategoryRepository categoryRepository,
    DateTime Function()? now,
  }) : auth = AuthPresenter(authRepository),
       overview = OverviewPresenter(overviewRepository, now: now),
       transactions = TransactionPresenter(transactionRepository),
       budgets = BudgetPresenter(budgetRepository),
       categories = CategoryPresenter(categoryRepository) {
    _subscriptions.add(
      auth.states.listen((state) {
        if (_accountId == state.account?.id) return;
        _accountId = state.account?.id;
        unawaited(overview.setAccount(state.account));
      }),
    );
    for (final presenter in [transactions, budgets, categories]) {
      _subscriptions.add(
        presenter.effects.listen((effect) {
          if (effect is DataChanged) {
            unawaited(
              effect.month == null
                  ? overview.reload()
                  : overview.showMonth(effect.month!),
            );
          }
        }),
      );
    }
  }
  Future<void> initialize() => auth.initialize();
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    auth.dispose();
    overview.dispose();
    transactions.dispose();
    budgets.dispose();
    categories.dispose();
  }
}
