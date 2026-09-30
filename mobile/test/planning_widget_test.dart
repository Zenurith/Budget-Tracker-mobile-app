import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/main.dart';
import 'package:pocketwise/views/planning_screen.dart';
import 'package:pocketwise/features/planning/presenter/planning_presenter.dart';
import 'support/fake_repositories.dart';

void main() {
  testWidgets('profile screen saves explicit income and no-debt confirmation', (
    tester,
  ) async {
    final repo = FakeRepositories()..account = testAccount;
    final planning = FakePlanningRepository();
    await tester.pumpWidget(
      PocketwiseApp(
        presenters: testPresenters(repo, planningRepository: planning),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Financial plan'));
    await tester.tap(find.text('Financial plan'));
    await tester.pumpAndSettle();
    expect(find.text('Inputs are incomplete'), findsOneWidget);
    await tester.tap(find.text('Review income & debt profile'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Timezone'),
      'Asia/Kuala_Lumpur',
    );
    await tester.tap(find.text('Add income source'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Salary',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Gross income (MYR) · optional'),
      '6000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Net income (MYR) · optional'),
      '5000',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not reviewed yet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I have no current debt').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.text('I have reviewed these income and debt inputs'),
    );
    await tester.tap(find.text('I have reviewed these income and debt inputs'));
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    expect(planning.savedProfile!['debt_confirmation'], 'none');
    expect(planning.savedProfile!['confirmed'], isTrue);
    expect(planning.savedProfile!['income_sources'][0]['net'], 500000);
    expect(planning.savedProfile!['timezone'], 'Asia/Kuala_Lumpur');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'payment requires explicit confirmation and preserves partial amount',
    (tester) async {
      final repo = FakePlanningRepository();
      final p = PlanningPresenter(repo);
      await p.setAccount(testAccount, DateTime(2026, 9));
      addTearDown(p.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentEditor(
              presenter: p,
              occurrence: {
                'id': 'due',
                'name': 'Rent',
                'remaining_amount': 10000,
              },
              currency: 'MYR',
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm payment'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (MYR)'),
        '40.00',
      );
      await tester.tap(
        find.text('I confirm this payment has already been made'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm payment'));
      await tester.pumpAndSettle();
      expect(repo.lastPayment!['amount'], 4000);
      expect(repo.lastPayment!['operation_id'], isNotEmpty);
      expect(repo.payments, 1);
    },
  );
}
