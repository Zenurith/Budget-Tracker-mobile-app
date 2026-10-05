import 'dart:async';
import 'package:test/test.dart';
import 'package:pocketwise/features/funding/presenter/funding_presenter.dart';
import 'package:pocketwise/models/finance.dart';
import 'support/fake_repositories.dart';

class PartialFundingRepository extends FakeFundingRepository {
  @override
  Future<Json> saveSnapshot(Json draft) async => {'revision': 1};
  @override
  Future<Json> savePlan(Json draft) async => {'revision': 1};
  @override
  Future<Json> saveGoal(Json draft, {String? id}) async => {'revision': 1};
  @override
  Future<Json> deleteGoal(String id, int revision) async => {'revision': 1};
}

void main() {
  test('funding writes reload wishlist quotes and purchase history', () async {
    final repo = PartialFundingRepository();
    final p = FundingPresenter(repo)..setAccount(testAccount);
    addTearDown(p.dispose);
    await p.reload();
    repo.data.addAll({
      'revision': 1,
      'wishlist': [
        {'id': 'camera', 'quote': 'new-quote'},
      ],
      'purchases': [
        {'id': 'purchase'},
      ],
      'categories': [
        {'id': 'shopping'},
      ],
    });
    for (final save in <Future<bool> Function()>[
      () => p.saveSnapshot({}),
      () => p.savePlan({}),
      () => p.saveGoal({}),
      () => p.deleteGoal('goal'),
    ]) {
      expect(await save(), true);
      expect(p.state.data['wishlist'][0]['quote'], 'new-quote');
      expect(p.state.data['purchases'][0]['id'], 'purchase');
      expect(p.state.data['categories'][0]['id'], 'shopping');
      expect(p.state.editable, true);
    }
  });
  test('owner and disposal suppress late funding reads', () async {
    final repo = FakeFundingRepository()..loadGate = Completer<Json>();
    final p = FundingPresenter(repo)..setAccount(testAccount);
    addTearDown(p.dispose);
    final work = p.reload();
    p.setAccount(null);
    repo.loadGate!.complete(repo.data);
    await work;
    expect(p.state.data, isEmpty);
    expect(await p.savePlan({}), false);
    p.setAccount(testAccount);
    repo.loadGate = Completer<Json>();
    final next = p.reload();
    p.dispose();
    repo.loadGate!.complete(repo.data);
    await next;
    expect(p.state.data, isEmpty);
  });
  test(
    'immutable state; new reload wins and failed reads block writes',
    () async {
      final repo = FakeFundingRepository()..loadGate = Completer<Json>();
      final old = repo.loadGate!;
      final p = FundingPresenter(repo)..setAccount(testAccount);
      addTearDown(p.dispose);
      final first = p.reload();
      repo.loadGate = null;
      repo.data['revision'] = 8;
      await p.reload();
      old.complete({...repo.data, 'revision': 1});
      await first;
      expect(p.state.data['revision'], 8);
      expect(() => p.state.data['goals'].add({}), throwsUnsupportedError);
      repo.failure = 'offline';
      await p.reload();
      expect(p.state.stale, true);
      expect(await p.saveSnapshot({}), false);
      repo.failure = null;
      await p.reload();
      expect(p.state.editable, true);
    },
  );
  test(
    'cash and plan requests use current revision and account currency',
    () async {
      final repo = FakeFundingRepository();
      final p = FundingPresenter(repo)..setAccount(testAccount);
      addTearDown(p.dispose);
      await p.reload();
      expect(
        await p.saveSnapshot({'currency': 'USD', 'confirmed': true}),
        true,
      );
      expect(repo.lastSnapshot!['currency'], 'MYR');
      expect(repo.lastSnapshot!['expected_revision'], 0);
      expect(repo.lastSnapshot!['expected_planning_revision'], 0);
      expect(await p.savePlan({'confirmed': true}), true);
      expect(repo.lastPlan!['expected_planning_revision'], 0);
    },
  );
  test(
    'allocation retries preserve keys through refresh; double clicks blocked',
    () async {
      final repo = FakeFundingRepository();
      final p = FundingPresenter(repo)..setAccount(testAccount);
      addTearDown(p.dispose);
      await p.reload();
      expect(
        await p.move('allocations', {'amount': 0, 'target_id': 'a'}),
        false,
      );
      expect(repo.moves, 0);
      repo.failure = 'timeout';
      final draft = {'amount': 500, 'target_id': 'a'};
      expect(await p.move('allocations', draft), false);
      final id = repo.lastMove!['operation_id'];
      repo.failure = null;
      await p.reload();
      repo.saveGate = Completer<Json>();
      final pending = p.move('allocations', draft);
      expect(await p.move('allocations', draft), false);
      expect(repo.lastMove!['operation_id'], id);
      repo.saveGate!.complete({'revision': 1});
      expect(await pending, true);
      expect(p.state.saving, false);
    },
  );
  test(
    'successful allocation is not repeated after a failed refresh',
    () async {
      final repo = FakeFundingRepository()..saveGate = Completer<Json>();
      final p = FundingPresenter(repo)..setAccount(testAccount);
      addTearDown(p.dispose);
      await p.reload();
      final pending = p.move('allocations', {'amount': 100, 'target_id': 'a'});
      repo.failure = 'refresh failed';
      repo.saveGate!.complete({'revision': 1});
      expect(await pending, true);
      expect(p.state.stale, true);
      expect(p.state.error, contains('refresh failed'));
      expect(repo.moves, 1);
    },
  );
  test('known changes invalidate funding until refreshed', () async {
    final repo = FakeFundingRepository();
    final p = FundingPresenter(repo)..setAccount(testAccount);
    addTearDown(p.dispose);
    await p.reload();
    p.invalidate(planningRevision: 0);
    expect(p.state.stale, false);
    p.invalidate(planningRevision: 1);
    expect(p.state.stale, true);
    expect(
      await p.move('allocations', {'amount': 100, 'target_id': 'a'}),
      false,
    );
    await p.reload();
    expect(p.state.editable, true);
    p.invalidate();
    expect(p.state.stale, true);
  });
}
