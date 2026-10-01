import '../../features/funding/model/funding_repository.dart';
import '../../features/funding/presenter/funding_presenter.dart';
import 'dart:async';
import '../../features/financial_helper/model/helper_repository.dart';
import '../../features/financial_helper/presenter/helper_presenter.dart';

import '../model/contracts.dart';
import 'presenter.dart';
import '../../features/auth/presenter/auth_presenter.dart';
import '../../features/overview/presenter/overview_presenter.dart';
import '../../features/transactions/presenter/transaction_presenter.dart';
import '../../features/transactions/presenter/history_presenter.dart';
import '../../features/planning/model/planning_repository.dart';
import '../../features/planning/presenter/planning_presenter.dart';
import '../../features/budgets/presenter/budget_presenter.dart';
import '../../features/categories/presenter/category_presenter.dart';

/// Presentation composition: relays typed effects, never exposes data adapters.
class AppPresenters {
  final AuthPresenter auth;
  final OverviewPresenter overview;
  final TransactionPresenter transactions;
  final HistoryPresenter history;
  final PlanningPresenter planning;
  final HelperPresenter helper;
  final FundingPresenter funding;
  final BudgetPresenter budgets;
  final CategoryPresenter categories;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Account? _account;
  final ExportDestination? exportDestination;
  AppPresenters({
    required AuthRepository authRepository,
    required OverviewRepository overviewRepository,
    required TransactionRepository transactionRepository,
    required BudgetRepository budgetRepository,
    required CategoryRepository categoryRepository,
    required PlanningRepository planningRepository,
    required HelperRepository helperRepository,
    required FundingRepository fundingRepository,
    this.exportDestination,
    DateTime Function()? now,
  }) : auth = AuthPresenter(authRepository),
       overview = OverviewPresenter(overviewRepository, now: now),
       transactions = TransactionPresenter(transactionRepository),
       history = HistoryPresenter(transactionRepository, now: now),
       planning = PlanningPresenter(planningRepository, now: now),
       helper = HelperPresenter(helperRepository),
       funding = FundingPresenter(fundingRepository),
       budgets = BudgetPresenter(budgetRepository),
       categories = CategoryPresenter(categoryRepository) {
    _subscriptions.add(
      auth.states.listen((state) {
        if (identical(_account, state.account)) return;
        final changedOwner = _account?.id != state.account?.id;
        _account = state.account;
        unawaited(overview.setAccount(state.account));
        if (changedOwner) {
          helper.setAccount(state.account);
          funding.setAccount(state.account);
          unawaited(history.setAccount(state.account, overview.month));
          unawaited(planning.setAccount(state.account, overview.month));
        }
      }),
    );
    _subscriptions.add(
      planning.states.listen((state) {
        if (!state.busy && !state.saving && state.data.isNotEmpty) {
          helper.invalidate(state.revision);
          funding.invalidate(planningRevision: state.revision);
        }
      }),
    );
    var historyMonth = overview.month;
    _subscriptions.add(
      overview.states.listen((state) {
        if (historyMonth != state.month) {
          historyMonth = state.month;
          unawaited(history.showMonth(state.month));
        }
      }),
    );
    for (final effects in [
      transactions.effects,
      budgets.effects,
      categories.effects,
      planning.effects,
    ]) {
      _subscriptions.add(
        effects.listen((effect) {
          if (effect is DataChanged) {
            funding.invalidate();
            unawaited(history.reload());
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
    history.dispose();
    planning.dispose();
    helper.dispose();
    funding.dispose();
    budgets.dispose();
    categories.dispose();
  }
}
