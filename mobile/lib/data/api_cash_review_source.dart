import '../services/api.dart';
import '../features/notifications/model/cash_review_repository.dart';

class ApiCashReviewSource implements CashReviewSource {
  final Api api;
  ApiCashReviewSource(this.api);
  @override
  Future<CashReviewPlan> load() async {
    final data = await api.request('GET', '/notifications/cash-review');
    return CashReviewPlan(
      ownerId: data['owner_id'],
      day: data['day'],
      needsReview: data['needs_review'],
      reason: data['reason'],
    );
  }
}
