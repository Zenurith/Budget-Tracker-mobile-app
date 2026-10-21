import '../../../models/finance.dart';

abstract interface class ScenarioRepository {
  Future<Json> load();
  Future<Json> save(Json draft);
  Future<void> delete(String id);
}
