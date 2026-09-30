import 'dart:async';
import 'package:test/test.dart';
import 'package:pocketwise/core/model/contracts.dart';
import 'package:pocketwise/models/finance.dart';
import 'package:pocketwise/features/transactions/presenter/history_presenter.dart';
import 'support/fake_repositories.dart';

Entry entry(String id) => Entry.fromJson({
  'id': id,
  'amount': 100,
  'type': 'expense',
  'category_id': 'food',
  'date': '2026-09-01',
});

void main() {
  test('new filters and sign-out invalidate pending results', () async {
    final pending = <Completer<EntryPage>>[];
    final repo = FakeRepositories()
      ..onSearch = (_, _) {
        final gate = Completer<EntryPage>();
        pending.add(gate);
        return gate.future;
      };
    final p = HistoryPresenter(repo);
    addTearDown(p.dispose);
    final first = p.setAccount(testAccount, DateTime(2026, 9));
    final next = p.apply(
      EntryFilter(
        start: DateTime(2026, 8),
        end: DateTime(2026, 9),
        query: 'new',
      ),
    );
    pending[1].complete(EntryPage([entry('new')], 1));
    await next;
    pending[0].complete(EntryPage([entry('old')], 1));
    await first;
    expect(p.state.entries.single.id, 'new');
    final late = p.reload();
    await p.setAccount(null, DateTime(2026, 9));
    pending[2].complete(EntryPage([entry('private')], 1));
    await late;
    expect(p.state.entries, isEmpty);
  });

  test(
    'pagination deduplicates records and preserves entries on failure',
    () async {
      final repo = FakeRepositories();
      final p = HistoryPresenter(repo);
      addTearDown(p.dispose);
      repo.onSearch = (_, page) async => EntryPage([entry('a')], 3);
      await p.setAccount(testAccount, DateTime(2026, 9));
      repo.failure = 'offline';
      await p.loadMore();
      expect(p.state.entries.single.id, 'a');
      expect(p.state.error, contains('offline'));
      expect(p.state.page, 1);
      repo.failure = null;
      repo.onSearch = (_, page) async =>
          EntryPage([entry('a'), entry('b'), entry('c')], 3);
      await p.loadMore();
      expect(p.state.entries.map((e) => e.id), ['a', 'b', 'c']);
      expect(p.state.error, isNull);
      expect(() => p.state.entries.clear(), throwsUnsupportedError);
    },
  );

  test(
    'invalid ranges never reach repository and month navigation retains criteria',
    () async {
      final repo = FakeRepositories();
      final p = HistoryPresenter(repo);
      addTearDown(p.dispose);
      await p.setAccount(testAccount, DateTime(2026, 9));
      final initial = repo.lastFilter;
      await p.apply(
        EntryFilter(start: DateTime(2026, 10), end: DateTime(2026, 9)),
      );
      expect(repo.lastFilter, initial);
      expect(p.state.error, isNotNull);
      await p.apply(
        EntryFilter(
          start: DateTime(2026, 9),
          end: DateTime(2026, 10),
          minAmount: 200,
          maxAmount: 100,
        ),
      );
      expect(repo.lastFilter, initial);
      await p.apply(
        EntryFilter(
          start: DateTime(2026, 9),
          end: DateTime(2026, 10),
          minAmount: 0,
          maxAmount: 200,
          query: 'food',
        ),
      );
      await p.showMonth(DateTime(2026, 2));
      expect(repo.lastFilter!.end, DateTime(2026, 2, 28));
      expect(repo.lastFilter!.query, 'food');
      expect(repo.lastFilter!.minAmount, 0);
    },
  );
}
