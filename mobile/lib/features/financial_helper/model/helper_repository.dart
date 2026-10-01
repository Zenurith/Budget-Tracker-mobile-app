import '../../../models/finance.dart';

abstract interface class HelperRepository {
  Future<Json> calculate();
  Future<Json> scenario(Json request);
  Future<Json> snapshots(int page);
  Future<Json> saveSnapshot(Json request);
}
