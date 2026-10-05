import 'dart:async';
import 'package:pocketwise/features/sync/model/sync_repository.dart';

class FakeSyncRepository implements SyncRepository {
  @override
  SyncState state = SyncState();
  final controller = StreamController<SyncState>.broadcast(sync: true);
  @override
  Stream<SyncState> get states => controller.stream;
  Completer<void>? gate;
  int calls = 0;
  String? resolved;
  bool? keptLocal;
  @override
  Future<void> synchronize() async {
    calls++;
    if (gate != null) await gate!.future;
    state = SyncState();
    controller.add(state);
  }

  @override
  Future<void> review(String id) async {
    controller.add(state);
  }

  @override
  Future<void> resolve(String id, {required bool useLocal}) async {
    resolved = id;
    keptLocal = useLocal;
    state = SyncState();
    controller.add(state);
  }
}
