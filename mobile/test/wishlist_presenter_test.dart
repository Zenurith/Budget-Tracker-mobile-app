import 'dart:async';
import 'package:test/test.dart';
import 'package:pocketwise/features/funding/presenter/funding_presenter.dart';
import 'package:pocketwise/models/finance.dart';
import 'support/fake_repositories.dart';

void main() {
  test(
    'purchase retries preserve operation and cash treatment; duplicate clicks blocked',
    () async {
      final repo = FakeFundingRepository();
      final p = FundingPresenter(repo)..setAccount(testAccount);
      addTearDown(p.dispose);
      await p.reload();
      final draft = {
        'amount': 50000,
        'baseline_effect': 'already_reconciled',
        'snapshot_token': 'snapshot',
        'transaction_id': 'expense',
      };
      repo.failure = 'timeout';
      expect(await p.recordPurchase('item', draft), false);
      final key = repo.lastPurchase!['operation_id'];
      repo.failure = null;
      repo.data['revision'] = 4;
      await p.reload();
      repo.saveGate = Completer<Json>();
      final pending = p.recordPurchase('item', draft);
      expect(await p.recordPurchase('item', draft), false);
      expect(repo.lastPurchase!['operation_id'], key);
      expect(repo.lastPurchase!['expected_revision'], 4);
      expect(repo.lastPurchase!['currency'], 'MYR');
      expect(repo.lastPurchase!['baseline_effect'], 'already_reconciled');
      expect(repo.lastPurchase!['transaction_id'], 'expense');
      repo.saveGate!.complete({'id': 'purchase'});
      expect(await pending, true);
    },
  );
  test(
    'committed purchase refresh failure stays successful and blocks stale writes',
    () async {
      final repo = FakeFundingRepository()..saveGate = Completer<Json>();
      final p = FundingPresenter(repo)..setAccount(testAccount);
      addTearDown(p.dispose);
      await p.reload();
      var effects = 0;
      final subscription = p.effects.listen((_) => effects++);
      addTearDown(subscription.cancel);
      final saving = p.recordPurchase('item', {'amount': 100});
      repo.failure = 'offline refresh';
      repo.saveGate!.complete({'id': 'purchase'});
      expect(await saving, true);
      expect(effects, 1);
      expect(p.state.stale, true);
      expect(await p.recordPurchase('item', {'amount': 100}), false);
      expect(repo.purchases, 1);
    },
  );
  test('logout suppresses a late purchase result and its effects', () async {
    final repo = FakeFundingRepository()..saveGate = Completer<Json>();
    final p = FundingPresenter(repo)..setAccount(testAccount);
    addTearDown(p.dispose);
    await p.reload();
    var effects = 0;
    p.effects.listen((_) => effects++);
    final saving = p.recordPurchase('item', {'amount': 100});
    p.setAccount(null);
    repo.saveGate!.complete({'id': 'purchase'});
    expect(await saving, false);
    expect(effects, 0);
    expect(p.state.data, isEmpty);
  });
  test(
    'wishlist edits use account revision; corrections have stable retry keys',
    () async {
      final repo = FakeFundingRepository();
      final p = FundingPresenter(repo)..setAccount(testAccount);
      addTearDown(p.dispose);
      await p.reload();
      expect(await p.saveWishlist({'name': 'Camera', 'currency': 'USD'}), true);
      expect(repo.lastWishlist!['currency'], 'MYR');
      expect(repo.lastWishlist!['expected_revision'], 0);
      repo.failure = 'timeout';
      final draft = {'confirmed': true, 'reason': 'Wrong link'};
      expect(await p.adjustPurchase('purchase', 'reverse', draft), false);
      final key = repo.lastAdjustment!['operation_id'];
      repo.failure = null;
      expect(await p.adjustPurchase('purchase', 'reverse', draft), true);
      expect(repo.lastAdjustment!['operation_id'], key);
      expect(
        repo.lastAdjustment!.containsKey('expected_planning_revision'),
        false,
      );
    },
  );
  test(
    'existing expense candidates exclude all linked records and are immutable',
    () async {
      final repo = FakeFundingRepository()
        ..expenseItems = [
          {'id': 'available'},
          {'id': 'bill', 'commitment_occurrence_id': 'due'},
          {'id': 'purchase', 'wishlist_purchase_id': 'p'},
        ];
      final p = FundingPresenter(repo)..setAccount(testAccount);
      addTearDown(p.dispose);
      final result = await p.purchaseExpenses('2026-10-02', 100);
      expect(result.map((e) => e['id']), ['available']);
      expect(() => result.first['id'] = 'changed', throwsUnsupportedError);
    },
  );
}
