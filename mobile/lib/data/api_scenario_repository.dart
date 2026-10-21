import '../features/debt_planner/model/scenario_repository.dart';
import '../models/finance.dart';
import '../services/api.dart';

class ApiScenarioRepository implements ScenarioRepository {
  final Api api;
  ApiScenarioRepository(this.api);
  @override
  Future<Json> load() => api.request('GET', '/debt-planner');
  @override
  Future<Json> save(Json draft) =>
      api.request('POST', '/debt-scenarios', body: draft);
  @override
  Future<void> delete(String id) async {
    await api.request('DELETE', '/debt-scenarios/${Uri.encodeComponent(id)}');
  }
}
