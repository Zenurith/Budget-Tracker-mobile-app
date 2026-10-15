import '../services/api.dart';
import '../features/notifications/model/bill_reminder_repository.dart';

class ApiBillReminderSource implements BillReminderSource {
  final Api api;
  ApiBillReminderSource(this.api);
  @override
  Future<BillReminderPlan> load(int leadDays) async {
    final data = await api.request(
      'GET',
      '/notifications/bills?lead_days=$leadDays',
    );
    return BillReminderPlan(
      ownerId: data['owner_id'],
      ready: data['ready'],
      reason: data['reason'],
      timezone: data['timezone'],
      windowEnd: data['window_end'],
      items: [
        for (final item in data['items'])
          BillReminder(
            id: item['id'],
            count: item['count'],
            dueDate: item['due_date'],
            fireAt: DateTime.parse(item['fire_at']),
          ),
      ],
    );
  }
}
