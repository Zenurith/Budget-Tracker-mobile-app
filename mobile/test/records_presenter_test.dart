import 'dart:async';
import 'package:test/test.dart';
import 'package:pocketwise/core/model/contracts.dart';
import 'package:pocketwise/features/records/presenter/records_presenter.dart';
import 'package:pocketwise/features/recovery/presenter/recovery_presenter.dart';
import 'package:pocketwise/models/finance.dart';
import 'support/fake_records.dart';

const account = Account(
  id: 'owner',
  name: 'Alex',
  email: 'alex@example.com',
  currency: 'EUR',
);

void main() {
  test(
    'CSV retries keep operation key and immutable previews; cancel keeps preview',
    () async {
      final repo = FakeRecords();
      final presenter = RecordsPresenter(repo, repo)..setAccount(account);
      expect(await presenter.pickCSV(), isTrue);
      expect(
        () => (presenter.state.preview['items'] as List).clear(),
        throwsUnsupportedError,
      );
      repo.contents = null;
      expect(await presenter.pickCSV(), isFalse);
      expect(presenter.state.preview['total'], 2);
      repo.failure = 'lost response';
      expect(await presenter.importCSV({1}, {}), isFalse);
      final id = repo.imports.single['operation_id'];
      repo.failure = null;
      expect(await presenter.importCSV({1}, {}), isTrue);
      expect(repo.imports.last['operation_id'], id);
      expect(presenter.state.preview, isEmpty);
      expect(presenter.state.message, contains('1 transactions'));
      presenter.dispose();
    },
  );
  test('late loads after logout cannot restore another account data', () async {
    final repo = FakeRecords()..pendingBalances = Completer<Json>();
    final presenter = RecordsPresenter(repo, repo)..setAccount(account);
    final pending = presenter.reload();
    expect(await presenter.reload(), isFalse);
    presenter.setAccount(null);
    repo.pendingBalances!.complete({
      'opening': {'total': 1000},
    });
    expect(await pending, isFalse);
    expect(presenter.state.balances, isEmpty);
    presenter.dispose();
  });
  test(
    'opening sends account currency, reviewed revision and stable retry key',
    () async {
      final repo = FakeRecords()
        ..balancesData = {
          'opening': {'revision': 3},
        };
      final presenter = RecordsPresenter(repo, repo)..setAccount(account);
      await presenter.reload();
      repo.failure = 'network';
      final draft = <String, dynamic>{
        'as_of': '2026-01-01',
        'accounts': [
          {'name': 'Cash', 'amount': 0},
        ],
        'confirmed': true,
      };
      expect(await presenter.saveOpening(draft), isFalse);
      repo.failure = null;
      expect(await presenter.saveOpening(draft), isTrue);
      expect(repo.openings.first['currency'], 'EUR');
      expect(repo.openings.first['expected_revision'], 3);
      expect(
        repo.openings.first['operation_id'],
        repo.openings.last['operation_id'],
      );
      presenter.dispose();
    },
  );
  test(
    'recovery validates, suppresses duplicate requests, then resets',
    () async {
      final repo = FakeRecords()..pendingRecovery = Completer<void>();
      final presenter = RecoveryPresenter(repo);
      expect(await presenter.request('bad'), isFalse);
      final request = presenter.request('alex@example.com');
      expect(await presenter.request('alex@example.com'), isFalse);
      expect(repo.requests, 1);
      repo.pendingRecovery!.complete();
      expect(await request, isTrue);
      expect(presenter.state.sent, isTrue);
      expect(
        await presenter.reset('x' * 43, 'password123', 'different'),
        isFalse,
      );
      expect(repo.resets, 0);
      expect(
        await presenter.reset('x' * 43, 'password123', 'password123'),
        isTrue,
      );
      expect(presenter.state.reset, isTrue);
      presenter.dispose();
    },
  );
}
