class BillReminder {
  final int id, count;
  final String dueDate;
  final DateTime fireAt;
  const BillReminder({
    required this.id,
    required this.count,
    required this.dueDate,
    required this.fireAt,
  });
}

class BillReminderPlan {
  final String ownerId;
  final bool ready;
  final String? timezone, windowEnd, reason;
  final List<BillReminder> items;
  BillReminderPlan({
    required this.ownerId,
    required this.ready,
    required List<BillReminder> items,
    this.timezone,
    this.windowEnd,
    this.reason,
  }) : items = List.unmodifiable(items);
}

abstract interface class BillReminderSource {
  Future<BillReminderPlan> load(int leadDays);
}

abstract interface class BillReminderScheduler {
  Future<void> setOwner(String? ownerId);
  Future<void> clear();
  Future<int> replace(List<BillReminder> reminders);
}
