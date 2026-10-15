import 'dart:async';
import 'package:pocketwise/features/notifications/model/bill_reminder_repository.dart';

BillReminderPlan reminderPlan([String owner = 'alex']) => BillReminderPlan(
  ownerId: owner,
  ready: true,
  timezone: 'Asia/Kuala_Lumpur',
  windowEnd: '2026-12-12',
  items: [
    BillReminder(
      id: 1,
      count: 2,
      dueDate: '2026-10-20',
      fireAt: DateTime.utc(2026, 10, 19, 1),
    ),
  ],
);

class FakeBillSource implements BillReminderSource {
  BillReminderPlan plan = reminderPlan();
  Completer<BillReminderPlan>? gate;
  bool fail = false;
  int loads = 0;
  int? lead;
  @override
  Future<BillReminderPlan> load(int leadDays) async {
    loads++;
    lead = leadDays;
    if (fail) throw StateError('Offline');
    return gate == null ? plan : await gate!.future;
  }
}

class FakeBillScheduler implements BillReminderScheduler {
  String? owner;
  List<BillReminder> pending = [];
  int clears = 0, replacements = 0;
  bool failClear = false;
  Completer<void>? replaceGate;
  @override
  Future<void> setOwner(String? ownerId) async {
    if (ownerId == null || owner != ownerId) await clear();
    owner = ownerId;
  }

  @override
  Future<void> clear() async {
    clears++;
    if (failClear) throw StateError('Cancellation failed');
    pending = [];
  }

  @override
  Future<int> replace(List<BillReminder> reminders) async {
    replacements++;
    if (replaceGate != null) await replaceGate!.future;
    pending = reminders;
    return pending.length;
  }
}
