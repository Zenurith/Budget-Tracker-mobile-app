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
  final offline = OfflineRepository(api, SecureOfflinePersistence(api.storage));
  api.beforeRequest = offline.guard;
  final finance = ApiFinanceRepository(api, offline: offline);
  return AppPresenters(
    authRepository: ApiAuthRepository(api, offline: offline),
    recordsRepository: ApiRecordsRepository(api),
    csvSource: FileCSVSource(),
    recoveryRepository: ApiRecoveryRepository(api),
    notificationRepository: DeviceNotificationRepository(api.storage),
    billReminderSource: ApiBillReminderSource(api),
    billReminderScheduler: LocalBillReminderScheduler(api.storage),
    syncRepository: offline,
    overviewRepository: finance,
    transactionRepository: finance,
    budgetRepository: finance,
    categoryRepository: finance,
    planningRepository: ApiPlanningRepository(api),
    helperRepository: ApiHelperRepository(api),
    fundingRepository: ApiFundingRepository(api),
    exportDestination: FileExportDestination(),
  );
}
