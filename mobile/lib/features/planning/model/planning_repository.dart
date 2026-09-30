import '../../../models/finance.dart';

abstract interface class PlanningRepository {
  Future<List<Entry>> expenses(DateTime month);
  Future<Json> load(DateTime month);
  Future<void> saveProfile(Json draft);
  Future<void> saveSchedule(String kind, Json draft, {String? id});
  Future<void> deleteSchedule(String kind, String id, int revision);
  Future<void> pay(String occurrenceId, Json payment);
  Future<void> unlink(String occurrenceId, String transactionId, int revision);
}
