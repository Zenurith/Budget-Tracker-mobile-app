import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/features/accounts/model/account_repository.dart';
import 'package:pocketwise/features/accounts/presenter/account_presenter.dart';
import 'package:pocketwise/models/finance.dart';
import 'package:pocketwise/views/accounts_screen.dart';
import 'support/fake_repositories.dart';

class Repository implements AccountRepository {
  Json data = {
    'items': [
      {
        'id': 'bank',
        'name': 'Bank',
        'opening_date': '2026-01-01',
        'opening_amount': 10000,
        'balance': 10000,
      },
      {
        'id': 'cash',
        'name': 'Cash',
        'opening_date': '2026-01-01',
        'opening_amount': 0,
        'balance': 0,
      },
    ],
    'as_of': '2026-10-19',
    'unassigned_count': 3,
    'transfers': [],
    'checks': [],
  };
  final saves = <Json>[];
  bool fail = false;
  Completer<Json>? gate;
  @override
  Future<Json> load() async => gate == null ? data : gate!.future;
  @override
  Future<void> save(String action, Json draft) async {
    saves.add(draft);
    if (fail) throw StateError('offline');
  }
}

void main() {
  test(
    'retry IDs persist and sync blocks mutations; logout rejects late reads',
    () async {
      final repo = Repository();
      var blocked = false;
      final p = AccountPresenter(repo, syncBlocked: () => blocked)
        ..setAccount(testAccount);
      addTearDown(p.dispose);
      repo.fail = true;
      expect(await p.save('transfer', {'amount': 100}), isFalse);
      final id = repo.saves.last['operation_id'];
      repo.fail = false;
      expect(await p.save('transfer', {'amount': 100}), isTrue);
      expect(repo.saves.last['operation_id'], id);
      blocked = true;
      expect(await p.save('transfer', {'amount': 200}), isFalse);
      expect(repo.saves.length, 2);
      blocked = false;
      repo.gate = Completer();
      final loading = p.reload();
      p.setAccount(null);
      repo.gate!.complete(repo.data);
      await loading;
      expect(p.state.data, isEmpty);
    },
  );
  testWidgets(
    'archived accounts remain visible and restore edits send reviewed revision',
    (tester) async {
      final repo = Repository();
      (repo.data['items'] as List).first['archived'] = true;
      (repo.data['items'] as List).first['revision'] = 4;
      final p = AccountPresenter(repo, syncBlocked: () => false)
        ..setAccount(testAccount);
      addTearDown(p.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AccountsScreen(presenter: p, currency: 'MYR'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bank · Archived'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Edit / archive account').first,
        200,
      );
      await tester.tap(find.text('Edit / archive account').first);
      await tester.pumpAndSettle();
      expect(find.text('Edit account'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Account name'),
        'Main bank',
      );
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.saves.single['account_id'], 'bank');
      expect(repo.saves.single['expected_revision'], 4);
      expect(repo.saves.single['name'], 'Main bank');
      expect(repo.saves.single['archived'], false);
      expect(repo.saves.single['opening_amount'], 10000);
      expect(repo.saves.single['opening_date'], '2026-01-01');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('account overview and transfer editor fit large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = Repository();
    final p = AccountPresenter(repo, syncBlocked: () => false)
      ..setAccount(testAccount);
    addTearDown(p.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AccountsScreen(presenter: p, currency: 'MYR'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Record transfer'), 250);
    await tester.tap(find.text('Record transfer'));
    await tester.pumpAndSettle();
    expect(find.text('From account'), findsOneWidget);
    expect(repo.saves, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
