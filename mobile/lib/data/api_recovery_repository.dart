import '../services/api.dart';
import '../features/recovery/model/recovery_repository.dart';

class ApiRecoveryRepository implements RecoveryRepository {
  final Api api;
  ApiRecoveryRepository(this.api);
  @override
  Future<void> requestReset(String email) async {
    await api.request(
      'POST',
      '/auth/password/request',
      body: {'email': email},
      retry: false,
    );
  }

  @override
  Future<void> resetPassword(String token, String password) async {
    await api.request(
      'POST',
      '/auth/password/reset',
      body: {'token': token, 'password': password},
      retry: false,
    );
    // Preserve any pending offline records for reauthentication with the new password.
    await api.clear();
  }
}
