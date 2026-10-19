class CashReviewPlan {
  final String ownerId, day, reason;
  final bool needsReview;
  const CashReviewPlan({
    required this.ownerId,
    required this.day,
    required this.needsReview,
    required this.reason,
  });
}

abstract interface class CashReviewSource {
  Future<CashReviewPlan> load();
}

abstract interface class CashReviewDelivery {
  Future<void> setOwner(String? owner);
  Future<void> clear();
  Future<void> forgetOwner(String owner);
  Future<int> deliver(CashReviewPlan plan);
}
