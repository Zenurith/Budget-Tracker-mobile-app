import '../data/api_funding_repository.dart';
import '../data/api_helper_repository.dart';
import '../core/presentation/app_presenters.dart';
import '../data/api_repositories.dart';
import '../services/api.dart';
import '../data/file_export_destination.dart';
import '../data/api_planning_repository.dart';

AppPresenters createPresenters() {
  final api = Api();
  final finance = ApiFinanceRepository(api);
  return AppPresenters(
    authRepository: ApiAuthRepository(api),
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
