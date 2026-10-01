import '../features/funding/model/funding_repository.dart';
import '../models/finance.dart';
import '../services/api.dart';

class ApiFundingRepository implements FundingRepository {
  final Api api;
  ApiFundingRepository(this.api);
  @override
  Future<Json> load() => api.request('GET', '/funding/availability');
  @override
  Future<Json> events(int page) =>
      api.request('GET', '/funding/events?page=$page');
  @override
  Future<Json> saveSnapshot(Json draft) =>
      api.request('PUT', '/funding/snapshot', body: draft);
  @override
  Future<Json> savePlan(Json draft) =>
      api.request('PUT', '/funding/plan', body: draft);
  @override
  Future<Json> saveGoal(Json draft, {String? id}) => api.request(
    id == null ? 'POST' : 'PUT',
    '/goals${id == null ? '' : '/${Uri.encodeComponent(id)}'}',
    body: draft,
  );
  @override
  Future<Json> deleteGoal(String id, int revision) => api.request(
    'DELETE',
    '/goals/${Uri.encodeComponent(id)}?expected_revision=$revision',
  );
  @override
  Future<Json> move(String kind, Json draft) =>
      api.request('POST', '/funding/$kind', body: draft);
}
