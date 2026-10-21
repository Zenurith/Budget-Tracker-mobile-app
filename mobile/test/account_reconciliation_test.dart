import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/views/account_reconciliation_panel.dart';

void main() {
  testWidgets(
    'difference direction, exact unassigned matches and duplicate clues',
    (tester) async {
      final entry = {
        'date': '2026-10-20',
        'kind': 'expense',
        'amount': -500,
        'note': 'Lunch',
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AccountReconciliationPanel(
                currency: 'MYR',
                actual: 9500,
                account: {
                  'name': 'Bank',
                  'balance': 10000,
                  'opening_date': '2020-01-01',
                  'opening_amount': 11000,
                  'review': {
                    'income': 0,
                    'expenses': 1000,
                    'transfers_in': 0,
                    'transfers_out': 0,
                    'activity_count': 2,
                    'activity': [entry, entry],
                  },
                },
                data: {
                  'as_of': '2026-10-21',
                  'unassigned_review': [
                    entry,
                    {...entry, 'amount': 500},
                  ],
                },
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('Actual cash is lower'), findsOneWidget);
      expect(find.text('1 unassigned amount matches'), findsOneWidget);
      expect(find.text('1 possible duplicate entries'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
