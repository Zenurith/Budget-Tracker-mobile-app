import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/features/funding/presenter/funding_presenter.dart';
import 'package:pocketwise/views/funding_screen.dart';
import 'support/fake_repositories.dart';

void main() {
  testWidgets(
    'cash confirmation is explicit and preserves named account balances',
    (tester) async {
      final repo = FakeFundingRepository();
      final p = FundingPresenter(repo)..setAccount(testAccount);
      addTearDown(p.dispose);
      await tester.pumpWidget(MaterialApp(home: FundingScreen(presenter: p)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Reconcile cash'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Reconcile cash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reconcile cash'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Account name'),
        'Debit account',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current balance (MYR)'),
        '4000.25',
      );
      await tester.ensureVisible(
        find.text(
          'I reconciled these balances, including outside spending and all reserves in these accounts',
        ),
      );
      await tester.tap(
        find.text(
          'I reconciled these balances, including outside spending and all reserves in these accounts',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(repo.lastSnapshot!['accounts'][0]['amount'], 400025);
      expect(repo.lastSnapshot!['confirmed'], true);
      expect(repo.lastSnapshot!['currency'], 'MYR');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('funding plan requires explicit zero amounts and confirmation', (
    tester,
  ) async {
    final repo = FakeFundingRepository();
    final p = FundingPresenter(repo)..setAccount(testAccount);
    addTearDown(p.dispose);
    await tester.pumpWidget(MaterialApp(home: FundingScreen(presenter: p)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review funding plan'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review funding plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review funding plan'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(
        TextFormField,
        'Additional cash buffer (MYR) · enter 0 if none',
      ),
      '0',
    );
    await tester.enterText(
      find.widgetWithText(
        TextFormField,
        'Monthly future surplus (MYR) · enter 0 or a shortfall',
      ),
      '-200',
    );
    await tester.ensureVisible(
      find.text(
        'I reviewed this horizon, all obligations, allowances and savings requirements, including any zero or none values',
      ),
    );
    await tester.tap(
      find.text(
        'I reviewed this horizon, all obligations, allowances and savings requirements, including any zero or none values',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(repo.lastPlan!['next_income_date'], isNull);
    expect(repo.lastPlan!['buffer_amount'], 0);
    expect(repo.lastPlan!['monthly_forecast_surplus'], -20000);
    expect(repo.lastPlan!['essential_allowances'], isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('phone at 200 percent text supports reservation confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeFundingRepository();
    repo.data.addAll({
      'usable': true,
      'can_allocate': true,
      'liquid_total': 400000,
      'free_to_allocate': 70000,
      'coverage_shortfall': 0,
      'goals': [
        {
          'id': 'goal',
          'name': 'Emergency',
          'kind': 'emergency',
          'target_amount': 100000,
          'included_in_cash': true,
          'funded_amount': 50000,
          'required_by': null,
        },
      ],
    });
    final p = FundingPresenter(repo)..setAccount(testAccount);
    addTearDown(p.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: FundingScreen(presenter: p),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Reserve cash'), 400);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reserve cash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reserve cash'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (MYR)'),
      '100',
    );
    await tester.ensureVisible(find.text('I confirm this reservation change'));
    await tester.tap(find.text('I confirm this reservation change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(repo.lastMove!['amount'], 10000);
    expect(repo.lastMove!['target_id'], 'goal');
    expect(repo.lastMove!['operation_id'], isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
