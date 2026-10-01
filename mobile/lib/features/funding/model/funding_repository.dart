import '../../../models/finance.dart';

abstract interface class FundingRepository {
  Future<Json> load();
  Future<Json> events(int page);
  Future<Json> saveSnapshot(Json draft);
  Future<Json> savePlan(Json draft);
  Future<Json> saveGoal(Json draft, {String? id});
  Future<Json> deleteGoal(String id, int revision);
  Future<Json> move(String kind, Json draft);
}
