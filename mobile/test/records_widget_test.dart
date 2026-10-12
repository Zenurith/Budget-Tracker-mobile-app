import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/core/model/contracts.dart';
import 'package:pocketwise/features/records/presenter/records_presenter.dart';
import 'package:pocketwise/features/recovery/presenter/recovery_presenter.dart';
import 'package:pocketwise/views/records_screen.dart';
import 'package:pocketwise/views/recovery_screen.dart';
import 'support/fake_records.dart';

const account = Account(
  id: 'owner',
  name: 'Alex',
  email: 'alex@example.com',
  currency: 'EUR',
);

void main() {
  testWidgets(
    'CSV preview leaves duplicates unselected and requires import confirmation',
    (tester) async {
      final repo = FakeRecords();
      final presenter = RecordsPresenter(repo, repo)..setAccount(account);
      await tester.pumpWidget(
        MaterialApp(
          home: RecordsScreen(
            presenter: presenter,
            currency: 'EUR',
            initialTab: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose CSV file'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 rows selected'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Import selected rows'),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('csv-records')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Import selected rows'));
      await tester.pumpAndSettle();
      expect(repo.imports, isEmpty);
      await tester.tap(find.text('Import').last);
      await tester.pumpAndSettle();
      expect(repo.imports.single['rows'], [1]);
      presenter.dispose();
    },
  );
  testWidgets('balance and recovery screens fit phone at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeRecords();
    final presenter = RecordsPresenter(repo, repo)..setAccount(account);
    Widget app(Widget child) => MaterialApp(
      builder: (context, page) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: page!,
      ),
      home: child,
    );
    await tester.pumpWidget(
      app(RecordsScreen(presenter: presenter, currency: 'EUR')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Set opening balances'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('balance-records')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Set opening balances'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    final recovery = RecoveryPresenter(repo);
    await tester.pumpWidget(app(RecoveryScreen(presenter: recovery)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'alex@example.com');
    await tester.ensureVisible(find.text('Send reset email'));
    await tester.tap(find.text('Send reset email'));
    await tester.pumpAndSettle();
    expect(repo.requests, 1);
    expect(tester.takeException(), isNull);
    presenter.dispose();
    recovery.dispose();
  });
}
