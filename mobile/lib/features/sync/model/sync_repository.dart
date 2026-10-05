import '../../../core/model/contracts.dart';
import '../../../models/finance.dart';

class SyncState {
  final List<Json> operations;
  final bool offline, busy;
  final String? error;
  SyncState({
    List<Json> operations = const [],
    this.offline = false,
    this.busy = false,
    this.error,
  }) : operations = List.unmodifiable(operations.map(freezeJson));
}

abstract interface class SyncRepository {
  SyncState get state;
  Stream<SyncState> get states;
  Future<void> synchronize();
  Future<void> review(String operationId);
  Future<void> resolve(String operationId, {required bool useLocal});
}

abstract interface class OfflinePersistence {
  Future<String?> read();
  Future<void> write(String? value);
}
