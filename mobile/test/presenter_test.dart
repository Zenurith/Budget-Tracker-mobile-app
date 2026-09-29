import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';
import 'package:pocketwise/core/model/contracts.dart';
import 'package:pocketwise/features/auth/presenter/auth_presenter.dart';
import 'package:pocketwise/features/overview/presenter/overview_presenter.dart';
import 'package:pocketwise/features/transactions/presenter/transaction_presenter.dart';
import 'package:pocketwise/features/budgets/presenter/budget_presenter.dart';
import 'package:pocketwise/features/categories/presenter/category_presenter.dart';
import 'support/fake_repositories.dart';

void main() {
  test('layers cannot import Flutter, HTTP, storage or concrete adapters', () {
    final lib = Directory('lib');
    for (final file
        in lib
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final path = file.path.replaceAll('\\', '/');
      final text = file.readAsStringSync();
      final imports = RegExp(
        r'''(?:import|export)\s+['"]([^'"]+)['"]''',
      ).allMatches(text).map((m) => m[1]!).toList();
      final presentation =
          path.contains('/presenter/') || path.contains('/presentation/');
      final model = path.contains('/model/') || path.contains('/models/');
      final view =
          path.contains('/views/') ||
          path.contains('/view/') ||
          path.contains('/widgets/');
      if (presentation || model) {
        expect(
          imports.where(
            (i) =>
                i.contains('package:flutter') ||
                i.contains('/services/') ||
                i.contains('/data/') ||
                i.contains('package:http') ||
                i.contains('storage'),
          ),
          isEmpty,
          reason: path,
        );
        expect(text.contains('BuildContext'), isFalse, reason: path);
      }
      if (view) {
        expect(
          imports.where(
            (i) =>
                i.contains('/services/') ||
                i.contains('/data/') ||
                i.contains('/composition/') ||
                i.contains('package:http') ||
                i.contains('storage'),
          ),
          isEmpty,
          reason: path,
        );
        expect(text.contains('.api.request'), isFalse, reason: path);
      }
    }
  });
  test(
    'authentication rejects missing currency and invalid inputs without I/O',
    () async {
      final repo = FakeRepositories();
      final p = AuthPresenter(repo);
      addTearDown(p.dispose);
      await p.initialize();
      expect(
        await p.authenticate(
          const AuthInput(
            mode: 'register',
            email: 'a@example.com',
            password: 'password1',
            name: 'A',
          ),
        ),
        isFalse,
      );
      expect(p.state.error, 'Choose your currency');
      expect(repo.authCalls, 0);
      expect(
        await p.authenticate(
          const AuthInput(
            mode: 'register',
            email: 'a@example.com',
            password: 'password1',
            name: 'A',
            currency: 'EUR',
          ),
        ),
        isTrue,
      );
      expect(repo.authCalls, 1);
    },
  );
  test('demo requires a supported currency before repository access', () async {
    final repo = FakeRepositories();
    final p = AuthPresenter(repo);
    addTearDown(p.dispose);
    await p.initialize();
    for (final currency in [null, '', 'JPY', 'usd']) {
      expect(
        await p.authenticate(AuthInput(mode: 'demo', currency: currency)),
        isFalse,
      );
      expect(p.state.error, 'Choose your currency');
      expect(repo.authCalls, 0);
    }
    expect(
      await p.authenticate(const AuthInput(mode: 'demo', currency: 'USD')),
      isTrue,
    );
    expect(repo.authCalls, 1);
    expect(repo.lastAuthInput!.currency, 'USD');
  });
  test('month responses cannot replace a newer selection', () async {
    final pending = <int, Completer<MonthlySnapshot>>{};
    final repo = FakeRepositories()
      ..onLoad = (date) =>
          (pending[date.month] = Completer<MonthlySnapshot>()).future;
    final p = OverviewPresenter(repo, now: () => DateTime(2026, 9));
    addTearDown(p.dispose);
    final old = p.setAccount(testAccount);
    final next = p.changeMonth(1);
    pending[10]!.complete(MonthlySnapshot(summary: {'income': 200}));
    await next;
    pending[9]!.complete(MonthlySnapshot(summary: {'income': 100}));
    await old;
    expect(p.month.month, 10);
    expect(p.summary['income'], 200);
  });
  test('logout invalidates in-flight account data', () async {
    final gate = Completer<MonthlySnapshot>();
    final repo = FakeRepositories()..onLoad = (_) => gate.future;
    final p = OverviewPresenter(repo);
    addTearDown(p.dispose);
    final loading = p.setAccount(testAccount);
    await p.setAccount(null);
    gate.complete(MonthlySnapshot(summary: {'income': 999}));
    await loading;
    expect(p.user, isNull);
    expect(p.summary, isEmpty);
  });
  test(
    'load failure retains data and marks it stale; retry clears error',
    () async {
      final repo = FakeRepositories()
        ..snapshot = MonthlySnapshot(summary: {'income': 100});
      final p = OverviewPresenter(repo);
      addTearDown(p.dispose);
      await p.setAccount(testAccount);
      repo.failure = 'offline';
      await p.reload();
      expect(p.state.stale, isTrue);
      expect(p.summary['income'], 100);
      expect(p.error, contains('offline'));
      repo.failure = null;
      await p.reload();
      expect(p.error, isNull);
      expect(p.state.stale, isFalse);
    },
  );
  test(
    'nested state is immutable, including chart maps and budget entries',
    () {
      final raw = <String, dynamic>{
        'category_breakdown': {'food': 100},
        'trend': [
          {'income': 200},
        ],
      };
      final snapshot = MonthlySnapshot(
        summary: raw,
        budgets: [
          {'limit_amount': 100},
        ],
      );
      (raw['category_breakdown'] as Map)['food'] = 9;
      expect(snapshot.summary['category_breakdown']['food'], 100);
      expect(
        () => snapshot.summary['category_breakdown']['food'] = 0,
        throwsUnsupportedError,
      );
      expect(
        () => snapshot.budgets.first['limit_amount'] = 0,
        throwsUnsupportedError,
      );
      expect(() => snapshot.entries.clear(), throwsUnsupportedError);
    },
  );
  test(
    'parse does not save; repeated submission is blocked until completion',
    () async {
      final repo = FakeRepositories()..saveGate = Completer<void>();
      final p = TransactionPresenter(repo);
      addTearDown(p.dispose);
      final parsed = await p.parse('Lunch 15.50', DateTime(2026, 9, 28));
      expect(parsed!.entry.amount, 1550);
      expect(repo.saves, isEmpty);
      final draft = EntryDraft(
        amount: 1550,
        type: 'expense',
        categoryId: 'food',
        date: DateTime(2026, 9, 27),
      );
      final first = p.save(draft);
      expect(p.state.busy, isTrue);
      expect(await p.save(draft), isFalse);
      expect(repo.saves, hasLength(1));
      repo.saveGate!.complete();
      expect(await first, isTrue);
      expect(p.state.busy, isFalse);
    },
  );
  test('disposed presenters suppress late results and effects', () async {
    final repo = FakeRepositories()..saveGate = Completer<void>();
    final p = TransactionPresenter(repo);
    var effects = 0;
    p.effects.listen((_) => effects++);
    final work = p.save(
      EntryDraft(
        amount: 100,
        type: 'expense',
        categoryId: 'food',
        date: DateTime(2026),
      ),
    );
    p.dispose();
    repo.saveGate!.complete();
    expect(await work, isFalse);
    expect(effects, 0);
  });
  test(
    'feature validation and server errors remain in presenter state',
    () async {
      final repo = FakeRepositories();
      final b = BudgetPresenter(repo);
      final c = CategoryPresenter(repo);
      addTearDown(b.dispose);
      addTearDown(c.dispose);
      expect(
        await b.save(
          const BudgetDraft(
            period: '2026-09',
            limitAmount: 100,
            alertThreshold: 101,
          ),
        ),
        isFalse,
      );
      expect(
        await c.save(const CategoryDraft(name: ' ', type: 'expense')),
        isFalse,
      );
      repo.failure = 'Category in use';
      expect(await c.delete('food'), isFalse);
      expect(c.state.error, contains('Category in use'));
    },
  );
}
