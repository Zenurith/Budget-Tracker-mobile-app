import '../data/api_scenario_repository.dart';
import '../data/api_forecast_repository.dart';
import '../data/api_account_repository.dart';
import '../data/api_cash_review_source.dart';
import '../data/local_cash_review_delivery.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../data/local_notification_runtime.dart';
import '../data/api_budget_review_repository.dart';
import '../features/notifications/presenter/notification_navigation_presenter.dart';
import '../data/api_budget_alert_source.dart';
import '../data/local_budget_alert_delivery.dart';
import '../data/api_funding_repository.dart';
import '../data/api_helper_repository.dart';
import '../core/presentation/app_presenters.dart';
import '../data/api_repositories.dart';
import '../services/api.dart';
import '../data/file_export_destination.dart';
import '../data/api_planning_repository.dart';
import '../data/offline_repository.dart';
import '../data/secure_offline_persistence.dart';
import '../data/api_records_repository.dart';
import '../data/api_recovery_repository.dart';
import '../data/device_notification_repository.dart';
import '../data/api_bill_reminder_source.dart';
import '../data/local_bill_reminder_scheduler.dart';

AppPresenters createPresenters() {
  final api = Api();
  final navigation = NotificationNavigationPresenter();
  final plugin = FlutterLocalNotificationsPlugin();
  final runtime = LocalNotificationRuntime(plugin, navigation.open);
  final offline = OfflineRepository(api, SecureOfflinePersistence(api.storage));
  api.beforeRequest = offline.guard;
  final finance = ApiFinanceRepository(api, offline: offline);
  return AppPresenters(
    notificationNavigation: navigation,
    initializeNotifications: runtime.initialize,
    budgetReviewRepository: ApiBudgetReviewRepository(api),
    forecastRepository: ApiForecastRepository(api),
    accountRepository: ApiAccountRepository(api),
    authRepository: ApiAuthRepository(api, offline: offline),
    recordsRepository: ApiRecordsRepository(api),
    csvSource: FileCSVSource(),
    recoveryRepository: ApiRecoveryRepository(api),
    notificationRepository: DeviceNotificationRepository(api.storage),
    cashReviewSource: ApiCashReviewSource(api),
    cashReviewDelivery: LocalCashReviewDelivery(
      api.storage,
      plugin: plugin,
      initializeNotifications: runtime.initialize,
    ),
    budgetAlertSource: ApiBudgetAlertSource(api),
    budgetAlertDelivery: LocalBudgetAlertDelivery(
      api.storage,
      plugin: plugin,
      initializeNotifications: runtime.initialize,
    ),
    billReminderSource: ApiBillReminderSource(api),
    billReminderScheduler: LocalBillReminderScheduler(
      api.storage,
      plugin: plugin,
      initializeNotifications: runtime.initialize,
    ),
    syncRepository: offline,
    overviewRepository: finance,
    transactionRepository: finance,
    budgetRepository: finance,
    categoryRepository: finance,
    planningRepository: ApiPlanningRepository(api),
    scenarioRepository: ApiScenarioRepository(api),
    helperRepository: ApiHelperRepository(api),
    fundingRepository: ApiFundingRepository(api),
    wishlistChat: (message) =>
        api.request('POST', '/wishlist/chat', body: message),
    exportDestination: FileExportDestination(),
  );
}
