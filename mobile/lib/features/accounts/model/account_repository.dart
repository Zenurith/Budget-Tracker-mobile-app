import '../../../models/finance.dart';

abstract interface class AccountRepository {
  Future<Json> load();
  Future<void> save(String action, Json draft);
}
