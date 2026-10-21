import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/features/debt_planner/model/repayment_plan.dart';
import 'package:pocketwise/views/debt_planner_screen.dart';

void main() {
  test('freed minimum rolls over in the same month', () {
    final r = simulateRepayment(
      [
        const RepaymentDebt('A', 5000, 0, 10000),
        const RepaymentDebt('B', 15000, 0, 10000),
      ],
      0,
      avalanche: false,
    );
    expect(r.months, 1);
    expect(r.interest, 0);
    expect(r.payoffMonths, [1, 1]);
  });
  test('monthly interest matches hand calculation', () {
    const debts = [RepaymentDebt('Loan', 10000, 1200, 5000)];
    final r = simulateRepayment(debts, 0, avalanche: true);
    expect(r.months, 3);
    expect(r.interest, 153);
    expect(simulateRepayment(debts, 5100, avalanche: true).months, 1);
  });
  test('strategy ordering changes payoff and interest', () {
    const debts = [
      RepaymentDebt('Small', 10000, 0, 1000),
      RepaymentDebt('High rate', 50000, 2400, 1000),
    ];
    final s = simulateRepayment(debts, 5000, avalanche: false);
    final a = simulateRepayment(debts, 5000, avalanche: true);
    expect(s.payoffMonths[0]!, lessThan(s.payoffMonths[1]!));
    expect(a.interest, lessThan(s.interest));
  });
  test('growing debt fails closed and invalid rates are rejected', () {
    final r = simulateRepayment(
      [const RepaymentDebt('Growing', 100000, 10000, 1)],
      0,
      avalanche: true,
    );
    expect(r.paidOff, false);
    expect(r.payoffMonths.single, isNull);
    expect(
      () => simulateRepayment(
        [const RepaymentDebt('Unknown', 10000, -1, 100)],
        0,
        avalanche: true,
      ),
      throwsArgumentError,
    );
  });
  testWidgets('calculate and invalidate after editing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DebtPlannerScreen(currency: 'MYR')),
    );
    final fields = find.byType(TextFormField);
    final values = ['2026-11', 'Phone loan', '100', '12', '50', '0'];
    for (var i = 0; i < values.length; i++) {
      await tester.ensureVisible(fields.at(i));
      await tester.enterText(fields.at(i), values[i]);
    }
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Compare repayment plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compare repayment plans'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -450),
    );
    await tester.pumpAndSettle();
    expect(find.text('Snowball'), findsOneWidget);
    expect(find.textContaining('Estimated debt-free: 2027-01'), findsWidgets);
    final extraField = find.widgetWithText(
      TextFormField,
      'Extra monthly payment (MYR) — enter 0 if none',
    );
    await tester.ensureVisible(extraField);
    await tester.enterText(extraField, '10');
    await tester.pump();
    expect(find.text('Snowball'), findsNothing);
  });
}
