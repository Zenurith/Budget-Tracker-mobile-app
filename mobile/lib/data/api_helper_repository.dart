import '../features/financial_helper/model/helper_repository.dart';
import '../models/finance.dart';
import '../services/api.dart';

class ApiHelperRepository implements HelperRepository {
  final Api api;
  ApiHelperRepository(this.api);
  @override
  Future<Json> calculate() =>
      api.request('POST', '/financial-helper/calculate', body: {});
  @override
  Future<Json> scenario(Json request) =>
      api.request('POST', '/financial-helper/scenarios', body: request);
  @override
  Future<Json> snapshots(int page) =>
      api.request('GET', '/financial-helper/snapshots?page=$page');
  @override
  Future<Json> saveSnapshot(Json request) =>
      api.request('POST', '/financial-helper/snapshots', body: request);
}
