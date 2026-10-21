import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/core/model/contracts.dart';
import 'package:pocketwise/models/finance.dart';
import 'package:pocketwise/views/entry_editor.dart';
import 'package:pocketwise/features/transactions/model/transaction_input_rules.dart';
import 'support/fake_repositories.dart';

class RecordingRepository extends FakeRepositories {
  String? savedId;
  @override
  Future<void> saveEntry(EntryDraft draft, {String? id}) async {
    savedId = id;
    await super.saveEntry(draft, id: id);
  }
}

void main() {
  test(
    'amount validation distinguishes missing, nonpositive, format and limit',
    () {
      expect(TransactionInputRules.amount(' '), 'Enter an amount');
      for (final value in ['0', '00.00', '-1.50']) {
        expect(
          TransactionInputRules.amount(value),
          contains('greater than zero'),
        );
      }
      for (final value in ['1.234', 'abc', '1,000', '1e3']) {
        expect(TransactionInputRules.amount(value), contains('decimal places'));
      }
      expect(
        TransactionInputRules.amount('1000000000.01'),
        contains('or less'),
      );
      expect(TransactionInputRules.amount('1000000000.00'), isNull);
      expect(TransactionInputRules.amount(' 15.50 '), isNull);
      expect(TransactionInputRules.note('a' * 501), isNotNull);
    },
  );

  for (final duplicate in [true, false]) {
    testWidgets(
      duplicate
          ? 'duplicate creates an unlinked manual transaction today'
          : 'edit preserves record identity and version',
      (tester) async {
        final repo = RecordingRepository()..account = testAccount;
        final app = testPresenters(repo);
        await app.initialize();
        await app.overview.reload();
        final entry = Entry.fromJson({
          'id': 'original',
          'version': 'original-version',
          'amount': 1550,
          'type': 'expense',
          'category_id': 'food',
          'date': '2020-01-02',
          'note': 'Lunch',
          'payment_method': 'Debit card',
          'source': 'nlp',
          'commitment_occurrence_id': 'bill',
          'wishlist_purchase_id': 'purchase',
        });
        final before = dateOf(DateTime.now());
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showEntryEditor(
                    context,
                    app,
                    entry: entry,
                    duplicate: duplicate,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          find.text(duplicate ? 'Duplicate transaction' : 'Edit transaction'),
          findsOneWidget,
        );
        expect(repo.saves, isEmpty);
        expect(find.text('15.50'), findsOneWidget);
        await tester.ensureVisible(find.text('Save transaction'));
        await tester.tap(find.text('Save transaction'));
        await tester.pumpAndSettle();
        expect(repo.saves, hasLength(1));
        final draft = repo.saves.single;
        expect(repo.savedId, duplicate ? isNull : 'original');
        expect(draft.expectedVersion, duplicate ? isNull : 'original-version');
        expect(draft.source, duplicate ? 'manual' : 'nlp');
        expect(
          dateOf(draft.date),
          duplicate ? anyOf(before, dateOf(DateTime.now())) : '2020-01-02',
        );
        expect(draft.amount, 1550);
        expect(draft.note, 'Lunch');
        expect(draft.paymentMethod, 'Debit card');
        expect(entry.id, 'original');
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      },
    );
  }
}
