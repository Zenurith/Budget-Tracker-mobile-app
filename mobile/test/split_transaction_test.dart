import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/core/model/contracts.dart';
import 'package:pocketwise/models/finance.dart';
import 'package:pocketwise/views/entry_editor.dart';
import 'support/fake_repositories.dart';

void main() {
  testWidgets('split copy preserves portions and blocks a mismatched total', (
    tester,
  ) async {
    final shopping = FinanceCategory.fromJson({
      'id': 'shopping',
      'name': 'Shopping',
      'type': 'expense',
      'icon': 'shopping_bag',
      'color': '#000000',
    });
    final repo = FakeRepositories()
      ..account = testAccount
      ..snapshot = MonthlySnapshot(categories: [food, shopping]);
    final app = testPresenters(repo);
    await app.initialize();
    await app.overview.reload();
    final entry = Entry.fromJson({
      'id': 'original',
      'amount': 15000,
      'type': 'expense',
      'category_id': 'food',
      'date': '2026-01-01',
      'splits': [
        {'category_id': 'food', 'amount': 9000},
        {'category_id': 'shopping', 'amount': 6000},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showEntryEditor(context, app, entry: entry, duplicate: true),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('90.00'), findsOneWidget);
    final splitAmount = find.widgetWithText(TextFormField, 'Split 2 amount');
    await tester.ensureVisible(splitAmount);
    await tester.enterText(splitAmount, '50');
    await tester.ensureVisible(find.text('Save transaction'));
    await tester.tap(find.text('Save transaction'));
    await tester.pumpAndSettle();
    expect(repo.saves, isEmpty);
    expect(find.textContaining('Use distinct categories'), findsOneWidget);
    await tester.ensureVisible(splitAmount);
    await tester.enterText(splitAmount, '60');
    await tester.ensureVisible(find.text('Save transaction'));
    await tester.tap(find.text('Save transaction'));
    await tester.pumpAndSettle();
    expect(repo.saves.single.splits.map((s) => s.amount), [9000, 6000]);
    expect(repo.saves.single.amount, 15000);
    expect(repo.saves.single.expectedVersion, isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
