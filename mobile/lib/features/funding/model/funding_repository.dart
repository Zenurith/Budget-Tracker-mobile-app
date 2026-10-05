import '../../../models/finance.dart';

abstract interface class FundingRepository {
  Future<Json> load();
  Future<Json> expenses(String date, int amount);
  Future<Json> saveWishlist(Json draft, {String? id});
  Future<Json> deleteWishlist(String id, int revision);
  Future<Json> purchase(String id, Json draft);
  Future<Json> adjustPurchase(String id, String kind, Json draft);
  Future<Json> events(int page);
  Future<Json> saveSnapshot(Json draft);
  Future<Json> savePlan(Json draft);
  Future<Json> saveGoal(Json draft, {String? id});
  Future<Json> deleteGoal(String id, int revision);
  Future<Json> move(String kind, Json draft);
}
