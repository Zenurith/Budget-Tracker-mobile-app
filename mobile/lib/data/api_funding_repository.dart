import '../features/funding/model/funding_repository.dart';
import '../models/finance.dart';
import '../services/api.dart';

class ApiFundingRepository implements FundingRepository {
  final Api api;
  ApiFundingRepository(this.api);
  @override
  Future<Json> load() => api.request('GET', '/wishlist');
  @override
  Future<Json> expenses(String date, int amount) async {
    final items = <Json>[];
    var page = 1;
    while (true) {
      final result = await api.request(
        'GET',
        '/transactions?type=expense&start=${Uri.encodeComponent(date)}&end=${Uri.encodeComponent(date)}&min_amount=$amount&max_amount=$amount&page_size=100&page=$page',
      );
      final batch = (result['items'] as List).cast<Json>();
      items.addAll(batch);
      if (batch.isEmpty || items.length >= (result['total'] as int)) break;
      page++;
    }
    return {'items': items};
  }

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
  @override
  Future<Json> saveWishlist(Json draft, {String? id}) => api.request(
    id == null ? 'POST' : 'PUT',
    '/wishlist${id == null ? '' : '/${Uri.encodeComponent(id)}'}',
    body: draft,
  );
  @override
  Future<Json> deleteWishlist(String id, int revision) => api.request(
    'DELETE',
    '/wishlist/${Uri.encodeComponent(id)}?expected_revision=$revision',
  );
  @override
  Future<Json> purchase(String id, Json draft) => api.request(
    'POST',
    '/wishlist/${Uri.encodeComponent(id)}/purchases',
    body: draft,
  );
  @override
  Future<Json> adjustPurchase(String id, String kind, Json draft) =>
      api.request(
        'POST',
        '/wishlist-purchases/${Uri.encodeComponent(id)}/$kind',
        body: draft,
      );
}
