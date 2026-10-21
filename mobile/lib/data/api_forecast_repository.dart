import '../features/forecast/model/forecast_repository.dart';
import '../models/finance.dart';
import '../services/api.dart';

class ApiForecastRepository implements ForecastRepository {
  final Api api;
  ApiForecastRepository(this.api);
  @override
  Future<Json> calculate(Json assumptions) =>
      api.request('POST', '/funding/forecast', body: assumptions);
}
