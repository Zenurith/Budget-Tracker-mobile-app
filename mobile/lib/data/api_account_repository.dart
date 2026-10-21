import '../features/accounts/model/account_repository.dart';
import '../models/finance.dart';
import '../services/api.dart';

class ApiAccountRepository implements AccountRepository {
  final Api api;
  ApiAccountRepository(this.api);
  @override
  Future<Json> load() => api.request('GET', '/money-accounts');
  @override
  Future<void> save(String action, Json draft) async {
    await api.request(
      'POST',
      action == 'update'
          ? '/money-accounts/update'
          : action == 'account'
          ? '/money-accounts'
          : action == 'transfer'
          ? '/account-transfers'
          : '/money-accounts/reconcile',
      body: draft,
    );
  }
}
