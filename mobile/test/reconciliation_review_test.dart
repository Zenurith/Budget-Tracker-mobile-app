import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/core/model/contracts.dart';
import 'package:pocketwise/features/records/presenter/records_presenter.dart';
import 'package:pocketwise/views/records_screen.dart';
import 'support/fake_records.dart';

void main() {
  testWidgets('difference explains sign without claiming a cause', (
    tester,
  ) async {
    for (final difference in [-1250, 1250, 0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReconciliationDifference(
              difference: difference,
              currency: 'EUR',
            ),
          ),
        ),
      );
      expect(
        find.textContaining(
          difference == 0
              ? 'matched'
              : difference < 0
              ? 'lower than recorded'
              : 'higher than recorded',
        ),
        findsOneWidget,
      );
      expect(
        find.text('What to check'),
        difference == 0 ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('recorded balance review includes the whole baseline period', (
    tester,
  ) async {
    final repo = FakeRecords()
      ..balancesData = {
        'opening': {'as_of': '2026-08-01', 'total': 10000, 'accounts': []},
        'recorded': {
          'as_of': '2026-10-19',
          'opening_total': 10000,
          'movement': -2500,
          'balance': 7500,
        },
        'items': [],
        'total': 0,
        'page': 1,
      };
    final presenter = RecordsPresenter(repo, repo)
      ..setAccount(
        const Account(id: 'a', name: 'A', email: 'a@b.com', currency: 'EUR'),
      );
    addTearDown(presenter.dispose);
    DateTime? start, end;
    await tester.pumpWidget(
      MaterialApp(
        home: RecordsScreen(
          presenter: presenter,
          currency: 'EUR',
          reviewTransactions: (a, b) async {
            start = a;
            end = b;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Review balance transactions'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('balance-records')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Review balance transactions'));
    expect(start, DateTime(2026, 8));
    expect(end, DateTime(2026, 10, 19));
    expect(repo.openings, isEmpty);
    expect(repo.imports, isEmpty);
  });

  testWidgets('difference guidance fits narrow screens at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: ReconciliationDifference(
                  difference: -1250,
                  currency: 'EUR',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
