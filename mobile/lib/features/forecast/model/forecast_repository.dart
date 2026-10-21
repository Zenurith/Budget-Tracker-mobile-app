import '../../../models/finance.dart';

abstract interface class ForecastRepository {
  Future<Json> calculate(Json assumptions);
}
