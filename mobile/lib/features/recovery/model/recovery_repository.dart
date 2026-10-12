abstract interface class RecoveryRepository {
  Future<void> requestReset(String email);
  Future<void> resetPassword(String token, String password);
}
