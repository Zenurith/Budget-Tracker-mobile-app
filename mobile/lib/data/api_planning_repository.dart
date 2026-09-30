import '../features/planning/model/planning_repository.dart';
import '../models/finance.dart';
import '../services/api.dart';

class ApiPlanningRepository implements PlanningRepository {
  final Api api;
  ApiPlanningRepository(this.api);
  @override
  Future<List<Entry>> expenses(DateTime month) async {
    final entries = <Entry>[];
    var received = 0;
    for (var page = 1; ; page++) {
      final result = await api.request(
        'GET',
        '/transactions?type=expense&start=${dateOf(DateTime(month.year, month.month))}&end=${dateOf(DateTime(month.year, month.month + 1, 0))}&page=$page&page_size=100',
      );
      final batch = (result['items'] as List)
          .map((e) => Entry.fromJson(e as Json))
          .toList();
      entries.addAll(batch.where((e) => e.commitmentOccurrenceId == null));
      received += batch.length;
      if (received >= (result['total'] as int) || batch.isEmpty) return entries;
    }
  }

  @override
  Future<Json> load(DateTime month) => api.request(
    'GET',
    '/planning?start=${dateOf(DateTime(month.year, month.month))}&end=${dateOf(DateTime(month.year, month.month + 1, 0))}',
  );
  @override
  Future<void> saveProfile(Json draft) async {
    await api.request('PUT', '/financial-profile', body: draft);
  }

  @override
  Future<void> saveSchedule(String kind, Json draft, {String? id}) async {
    await api.request(
      id == null ? 'POST' : 'PUT',
      '/$kind${id == null ? '' : '/${Uri.encodeComponent(id)}'}',
      body: draft,
    );
  }

  @override
  Future<void> deleteSchedule(String kind, String id, int revision) async {
    await api.request(
      'DELETE',
      '/$kind/${Uri.encodeComponent(id)}?expected_revision=$revision',
    );
  }

  @override
  Future<void> pay(String occurrenceId, Json payment) async {
    await api.request(
      'POST',
      '/commitment-occurrences/${Uri.encodeComponent(occurrenceId)}/payments',
      body: payment,
    );
  }

  @override
  Future<void> unlink(
    String occurrenceId,
    String transactionId,
    int revision,
  ) async {
    await api.request(
      'DELETE',
      '/commitment-occurrences/${Uri.encodeComponent(occurrenceId)}/payments/${Uri.encodeComponent(transactionId)}?expected_revision=$revision',
    );
  }
}
