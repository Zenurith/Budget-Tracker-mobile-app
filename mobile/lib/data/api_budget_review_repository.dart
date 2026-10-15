import '../models/finance.dart';
import '../features/budgets/model/budget_review_repository.dart';
import '../services/api.dart';

class ApiBudgetReviewRepository implements BudgetReviewRepository {
  final Api api;
  ApiBudgetReviewRepository(this.api);
  @override
  Future<Json> load(String period) => api.request(
    'GET',
    '/budgets/review?period=${Uri.encodeQueryComponent(period)}',
  );
}
