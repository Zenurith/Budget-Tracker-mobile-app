import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/features/reports/model/spending_trends.dart';
import 'package:pocketwise/views/spending_trends_panel.dart';
import 'package:pocketwise/models/finance.dart';

final months = <Json>[
  for (var i = 1; i <= 6; i++)
    {
      'month': '2026-0$i',
      'expense': i * 100,
      'status': i == 6 ? 'in_progress' : 'ended',
      'category_totals': {'food': i * 100},
      'record_count': 1,
      'recorded_days': 1,
    },
];
void main() {
  test('window and ended-month average exclude partial month', () {
    final trend = SpendingTrends(months, 3);
    expect(trend.months.length, 3);
    expect(trend.average, 450);
    expect(trend.total('food'), 1500);
    expect(trend.change('food'), 200);
    expect(SpendingTrends([], 6).average, isNull);
    expect(SpendingTrends(months, 6).average, 300);
  });
  testWidgets('switches window with cached and partial labels at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SpendingTrendsPanel(
                months: months,
                currency: 'EUR',
                categoryName: (_) => 'Food',
                cached: true,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('across 2 ended months'), findsOneWidget);
    await tester.tap(find.text('6 months'));
    await tester.pump();
    expect(find.textContaining('across 5 ended months'), findsOneWidget);
    expect(find.text('Month in progress · partial totals'), findsOneWidget);
    expect(find.textContaining('Cached estimates'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
