import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../features/sync/model/sync_repository.dart';

class SecureOfflinePersistence implements OfflinePersistence {
  final FlutterSecureStorage storage;
  SecureOfflinePersistence(this.storage);
  static const key = 'pocketwise_offline_v1';
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String? value) => value == null
      ? storage.delete(key: key)
      : storage.write(key: key, value: value);
}
