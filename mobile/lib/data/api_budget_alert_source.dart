import '../services/api.dart';
import '../features/notifications/model/budget_alert_repository.dart';

class ApiBudgetAlertSource implements BudgetAlertSource {
  final Api api;
  ApiBudgetAlertSource(this.api);
  @override
  Future<BudgetAlertPlan> load() async {
    final data = await api.request('GET', '/notifications/budgets');
    return BudgetAlertPlan(
      ownerId: data['owner_id'],
      ready: data['ready'],
      period: data['period'],
      timezone: data['timezone'],
      reason: data['reason'],
      budgetIds: [for (final item in data['items']) item['id'] as String],
    );
  }
}
