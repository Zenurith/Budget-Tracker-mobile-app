import '../../features/notifications/presenter/notification_navigation_presenter.dart';
import '../../features/budgets/model/budget_review_repository.dart';
import '../../features/budgets/presenter/budget_review_presenter.dart';
import '../../features/notifications/model/budget_alert_repository.dart';
import '../../features/notifications/presenter/budget_alert_presenter.dart';
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
import '../../features/sync/model/sync_repository.dart';
import '../../features/sync/presenter/sync_presenter.dart';
import '../../features/records/model/records_repository.dart';
import '../../features/records/presenter/records_presenter.dart';
import '../../features/recovery/model/recovery_repository.dart';
import '../../features/recovery/presenter/recovery_presenter.dart';
import '../../features/notifications/model/notification_repository.dart';
import '../../features/notifications/presenter/notification_presenter.dart';
import '../../features/notifications/model/bill_reminder_repository.dart';
import '../../features/notifications/presenter/bill_reminder_presenter.dart';

/// Presentation composition: relays typed effects, never exposes data adapters.
class AppPresenters {
  final NotificationNavigationPresenter notificationNavigation;
  final Future<void> Function()? initializeNotifications;
  final BudgetReviewPresenter? budgetReview;
  final AuthPresenter auth;
  final OverviewPresenter overview;
  final TransactionPresenter transactions;
  final HistoryPresenter history;
  final PlanningPresenter planning;
  final HelperPresenter helper;
  final FundingPresenter funding;
  final BudgetPresenter budgets;
  final CategoryPresenter categories;
  final SyncPresenter? sync;
  final RecordsPresenter? records;
  final RecoveryPresenter? recovery;
  final NotificationPresenter? notifications;
  final BillReminderPresenter? billReminders;
  final BudgetAlertPresenter? budgetAlerts;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Account? _account;
  final ExportDestination? exportDestination;
  AppPresenters({
    NotificationNavigationPresenter? notificationNavigation,
    this.initializeNotifications,
    BudgetReviewRepository? budgetReviewRepository,
    required AuthRepository authRepository,
    required OverviewRepository overviewRepository,
    required TransactionRepository transactionRepository,
    required BudgetRepository budgetRepository,
    required CategoryRepository categoryRepository,
    required PlanningRepository planningRepository,
    required HelperRepository helperRepository,
    required FundingRepository fundingRepository,
    this.exportDestination,
    SyncRepository? syncRepository,
    RecordsRepository? recordsRepository,
    CSVSource? csvSource,
    RecoveryRepository? recoveryRepository,
    NotificationRepository? notificationRepository,
    BudgetAlertSource? budgetAlertSource,
    BudgetAlertDelivery? budgetAlertDelivery,
    BillReminderSource? billReminderSource,
    BillReminderScheduler? billReminderScheduler,
    DateTime Function()? now,
  }) : notificationNavigation =
           notificationNavigation ?? NotificationNavigationPresenter(),
       budgetReview = budgetReviewRepository == null
           ? null
           : BudgetReviewPresenter(
               budgetReviewRepository,
               syncBlocked: () =>
                   syncRepository != null &&
                   (syncRepository.state.offline ||
                       syncRepository.state.busy ||
                       syncRepository.state.operations.isNotEmpty),
             ),
       budgetAlerts =
           notificationRepository == null ||
               budgetAlertSource == null ||
               budgetAlertDelivery == null
           ? null
           : BudgetAlertPresenter(
               notificationRepository,
               budgetAlertSource,
               budgetAlertDelivery,
               syncBlocked: () =>
                   syncRepository != null &&
                   (syncRepository.state.offline ||
                       syncRepository.state.busy ||
                       syncRepository.state.operations.isNotEmpty),
             ),
       billReminders =
           notificationRepository == null ||
               billReminderSource == null ||
               billReminderScheduler == null
           ? null
           : BillReminderPresenter(
               notificationRepository,
               billReminderSource,
               billReminderScheduler,
             ),
       notifications = notificationRepository == null
           ? null
           : NotificationPresenter(notificationRepository),
       records = recordsRepository == null || csvSource == null
           ? null
           : RecordsPresenter(recordsRepository, csvSource),
       recovery = recoveryRepository == null
           ? null
           : RecoveryPresenter(recoveryRepository),
       sync = syncRepository == null ? null : SyncPresenter(syncRepository),
       auth = AuthPresenter(authRepository),
       overview = OverviewPresenter(overviewRepository, now: now),
       transactions = TransactionPresenter(transactionRepository),
       history = HistoryPresenter(transactionRepository, now: now),
       planning = PlanningPresenter(planningRepository, now: now),
       helper = HelperPresenter(helperRepository),
       funding = FundingPresenter(fundingRepository),
       budgets = BudgetPresenter(budgetRepository),
       categories = CategoryPresenter(categoryRepository) {
    auth.beforeAccountDeletion = budgetAlerts?.forgetOwner;
    auth.beforeSessionEnd = () async {
      this.notificationNavigation.clear();
      budgetReview?.setAccount(null);
      // Start both invalidations before awaiting either device queue.
      await Future.wait([
        if (billReminders != null) billReminders!.endSession(),
        if (budgetAlerts != null) budgetAlerts!.endSession(),
      ]);
    };
    notifications?.onChanged = (invalidate) async {
      await Future.wait([
        if (billReminders != null)
          billReminders!.refresh(invalidate: invalidate),
        if (budgetAlerts != null) budgetAlerts!.refresh(),
      ]);
    };
    _subscriptions.add(
      planning.effects.listen((effect) {
        if (effect is DataChanged) {
          unawaited(billReminders?.refresh(invalidate: true));
        }
      }),
    );
    _subscriptions.add(
      auth.states.listen((state) {
        if (!state.starting) {
          this.notificationNavigation.setAccount(state.account);
          budgetReview?.setAccount(state.account);
          unawaited(billReminders?.setAccount(state.account));
          unawaited(budgetAlerts?.setAccount(state.account));
        }
        if (identical(_account, state.account)) return;
        final changedOwner = _account?.id != state.account?.id;
        _account = state.account;
        unawaited(overview.setAccount(state.account));
        if (changedOwner) {
          records?.setAccount(state.account);
          if (state.account != null) unawaited(sync?.synchronize());
          helper.setAccount(state.account);
          funding.setAccount(state.account);
          unawaited(history.setAccount(state.account, overview.month));
          unawaited(planning.setAccount(state.account, overview.month));
        }
      }),
    );
    if (sync != null) {
      _subscriptions.add(
        sync!.states.listen((state) {
          if (state.operations.isNotEmpty || state.offline) {
            funding.invalidate();
            budgetReview?.invalidate();
            unawaited(budgetAlerts?.refresh());
          }
        }),
      );
      _subscriptions.add(
        sync!.effects.listen((effect) {
          if (effect is DataChanged) {
            funding.invalidate();
            budgetReview?.invalidate();
            unawaited(budgetAlerts?.refresh());
            unawaited(billReminders?.refresh());
            unawaited(history.reload());
            unawaited(overview.reload());
          }
        }),
      );
    }
    _subscriptions.add(
      planning.states.listen((state) {
        if (!state.busy && !state.saving && state.data.isNotEmpty) {
          helper.invalidate(state.revision);
          funding.invalidate(planningRevision: state.revision);
        }
      }),
    );
    _subscriptions.add(
      funding.effects.listen((effect) {
        if (effect is DataChanged) {
          budgetReview?.invalidate();
          unawaited(budgetAlerts?.refresh());
          unawaited(history.reload());
          unawaited(overview.reload());
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
      if (records != null) records!.effects,
    ]) {
      _subscriptions.add(
        effects.listen((effect) {
          if (effect is DataChanged) {
            funding.invalidate();
            budgetReview?.invalidate();
            unawaited(budgetAlerts?.refresh());
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
  Future<void> initialize() async {
    await auth.initialize();
    try {
      await initializeNotifications?.call();
    } catch (_) {
      /* Scheduling status provides retry. */
    }
  }

  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    notificationNavigation.dispose();
    budgetReview?.dispose();
    auth.dispose();
    overview.dispose();
    transactions.dispose();
    history.dispose();
    planning.dispose();
    helper.dispose();
    funding.dispose();
    budgets.dispose();
    categories.dispose();
    sync?.dispose();
    records?.dispose();
    recovery?.dispose();
    notifications?.dispose();
    billReminders?.dispose();
    budgetAlerts?.dispose();
  }
}
