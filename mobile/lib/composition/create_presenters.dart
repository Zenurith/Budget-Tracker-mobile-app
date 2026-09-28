import '../core/presentation/app_presenters.dart';
import '../data/api_repositories.dart';
import '../services/api.dart';

AppPresenters createPresenters() {
  final api = Api();
  final finance = ApiFinanceRepository(api);
  return AppPresenters(
    authRepository: ApiAuthRepository(api),
    overviewRepository: finance,
    transactionRepository: finance,
    budgetRepository: finance,
    categoryRepository: finance,
  );
}
