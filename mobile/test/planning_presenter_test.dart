import 'dart:async';
import 'package:test/test.dart';
import 'package:pocketwise/features/planning/presenter/planning_presenter.dart';
import 'package:pocketwise/models/finance.dart';
import 'support/fake_repositories.dart';

void main() {
  test('planning clears owner data and suppresses late responses', () async {
    final repo = FakePlanningRepository()..loadGate = Completer<Json>();
    final p = PlanningPresenter(repo);
    addTearDown(p.dispose);
    final pending = p.setAccount(testAccount, DateTime(2026, 9));
    await p.setAccount(null, DateTime(2026, 9));
    repo.loadGate!.complete({
      'revision': 3,
      'profile': {'timezone': 'Private'},
    });
    await pending;
    expect(p.state.data, isEmpty);
    expect(await p.saveProfile({}), isFalse);
  });

  test(
    'plan snapshots are immutable and saves send owner currency and revision',
    () async {
      final repo = FakePlanningRepository();
      final p = PlanningPresenter(repo);
      addTearDown(p.dispose);
      await p.setAccount(testAccount, DateTime(2026, 9));
      expect(() => p.state.data['debts'].add({}), throwsUnsupportedError);
      expect(
        await p.saveProfile({'timezone': 'UTC', 'currency': 'USD'}),
        isTrue,
      );
      expect(repo.savedProfile!['currency'], 'MYR');
      expect(repo.savedProfile!['expected_revision'], 0);
    },
  );

  test(
    'failed payment retries keep an operation ID and duplicate clicks are blocked',
    () async {
      final repo = FakePlanningRepository();
      final p = PlanningPresenter(repo);
      addTearDown(p.dispose);
      await p.setAccount(testAccount, DateTime(2026, 9));
      repo.failure = 'connection lost';
      final draft = {'amount': 100, 'date': '2026-09-01'};
      expect(await p.pay('due', draft), isFalse);
      final firstId = repo.lastPayment!['operation_id'];
      repo.failure = null;
      repo.paymentGate = Completer<void>();
      final pending = p.pay('due', draft);
      expect(await p.pay('due', {'amount': 200}), isFalse);
      expect(repo.lastPayment!['operation_id'], firstId);
      expect(repo.payments, 2);
      repo.paymentGate!.complete();
      expect(await pending, isTrue);
    },
  );

  test(
    'a committed save with failed refresh is not reported as an uncommitted action',
    () async {
      final repo = FakePlanningRepository();
      final p = PlanningPresenter(repo);
      addTearDown(p.dispose);
      await p.setAccount(testAccount, DateTime(2026, 9));
      repo.failure = 'refresh unavailable';
      expect(await p.saveProfile({'timezone': 'UTC'}), isTrue);
      expect(p.state.error, contains('refresh unavailable'));
      expect(p.state.saving, isFalse);
      repo.failure = null;
      await p.reload();
      expect(p.state.error, isNull);
    },
  );
}
