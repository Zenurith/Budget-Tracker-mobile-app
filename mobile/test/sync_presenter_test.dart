import 'dart:async';
import 'package:test/test.dart';
import 'package:pocketwise/features/sync/model/sync_repository.dart';
import 'package:pocketwise/features/sync/presenter/sync_presenter.dart';
import 'support/fake_sync_repository.dart';

void main() {
  test(
    'sync blocks duplicate requests and disposal suppresses late effects',
    () async {
      final repo = FakeSyncRepository()..gate = Completer<void>();
      final p = SyncPresenter(repo);
      addTearDown(repo.controller.close);
      var effects = 0;
      p.effects.listen((_) => effects++);
      final first = p.synchronize();
      await p.synchronize();
      expect(repo.calls, 1);
      expect(p.state.busy, true);
      p.dispose();
      repo.gate!.complete();
      await first;
      expect(effects, 0);
    },
  );
  test(
    'sync snapshots cannot be changed by views and choices are explicit',
    () async {
      final repo = FakeSyncRepository()
        ..state = SyncState(
          operations: [
            {
              'request': {'operation_id': 'one'},
              'status': 'conflict',
            },
          ],
        );
      final p = SyncPresenter(repo);
      addTearDown(p.dispose);
      addTearDown(repo.controller.close);
      expect(
        () => p.state.operations.single['request']['operation_id'] = 'changed',
        throwsUnsupportedError,
      );
      await p.resolve('one', useLocal: false);
      expect(repo.resolved, 'one');
      expect(repo.keptLocal, false);
      expect(p.state.operations, isEmpty);
    },
  );
}
