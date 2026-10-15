class BudgetAlertPlan {
  final String ownerId;
  final bool ready;
  final String? period, timezone, reason;
  final List<String> budgetIds;
  BudgetAlertPlan({
    required this.ownerId,
    required this.ready,
    this.period,
    this.timezone,
    this.reason,
    Iterable<String> budgetIds = const [],
  }) : budgetIds = List.unmodifiable(budgetIds);
}

abstract interface class BudgetAlertSource {
  Future<BudgetAlertPlan> load();
}

abstract interface class BudgetAlertDelivery {
  Future<void> setOwner(String? owner);
  Future<void> clear();
  Future<void> forgetOwner(String owner);

  /// Returns how many previously unnotified budgets were included.
  Future<int> deliver(BudgetAlertPlan plan);
}
