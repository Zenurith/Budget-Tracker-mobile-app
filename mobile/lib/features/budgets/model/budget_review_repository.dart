import '../../../models/finance.dart';

abstract interface class BudgetReviewRepository {
  Future<Json> load(String period);
}

class BudgetReviewTarget {
  final String ownerId, period;
  final List<String> ids;
  BudgetReviewTarget(this.ownerId, this.period, Iterable<String> ids)
    : ids = List.unmodifiable(ids);
}
