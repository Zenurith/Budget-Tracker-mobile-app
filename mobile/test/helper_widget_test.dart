import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/features/financial_helper/presenter/helper_presenter.dart';
import 'package:pocketwise/views/financial_helper_screen.dart';
import 'support/fake_repositories.dart';

void main() {
  testWidgets('baseline, what-if comparison and explicit save', (tester) async {
    final repo = FakeHelperRepository();
    final p = HelperPresenter(repo)..setAccount(testAccount);
    addTearDown(p.dispose);
    await tester.pumpWidget(
      MaterialApp(home: FinancialHelperScreen(presenter: p)),
    );
    await tester.pumpAndSettle();
    expect(find.text('DSR · net income basis: 22.00%'), findsOneWidget);
    expect(repo.saves, 0);
    await tester.ensureVisible(find.text('Try a what-if scenario'));
    await tester.tap(find.text('Try a what-if scenario'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Additional monthly debt payment'),
      '400',
    );
    await tester.tap(find.text('Compare scenario'));
    await tester.pumpAndSettle();
    expect(repo.lastScenario!['assumptions']['additional_debt_monthly'], 40000);
    expect(repo.saves, 0);
    await tester.scrollUntilVisible(find.text('Save scenario snapshot'), 200);
    await tester.tap(find.text('Save scenario snapshot'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Snapshot name'),
      'New car',
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(repo.saves, 1);
    expect(repo.lastSave!['name'], 'New car');
    expect(repo.lastSave!['assumptions']['additional_debt_monthly'], 40000);
    expect(find.text('Snapshot saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('incomplete inputs stay unavailable and error can retry', (
    tester,
  ) async {
    final repo = FakeHelperRepository()..failure = 'Offline';
    repo.baseline['complete'] = false;
    repo.baseline['ratios']['dsr']['value'] = null;
    repo.baseline['missing_inputs'] = [
      {'message': 'Confirm your debt list.'},
    ];
    final p = HelperPresenter(repo)..setAccount(testAccount);
    addTearDown(p.dispose);
    await tester.pumpWidget(
      MaterialApp(home: FinancialHelperScreen(presenter: p)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Offline'), findsOneWidget);
    repo.failure = null;
    await tester.tap(find.text('Retry / refresh'));
    await tester.pumpAndSettle();
    expect(find.text('DSR · net income basis: Unavailable'), findsOneWidget);
    expect(find.text('• Confirm your debt list.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('results and scenario fields fit a phone at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeHelperRepository();
    final p = HelperPresenter(repo)..setAccount(testAccount);
    addTearDown(p.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: FinancialHelperScreen(presenter: p),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Try a what-if scenario'), 200);
    await tester.tap(find.text('Try a what-if scenario'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.saves, 0);
  });
}
