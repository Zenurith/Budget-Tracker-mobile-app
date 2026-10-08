import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/main.dart';
import 'package:pocketwise/features/overview/presenter/overview_presenter.dart';
import 'package:pocketwise/views/dashboard_plan_summary.dart';
import 'package:pocketwise/widgets/charts.dart';
import 'dashboard_test.dart' show PreviewRepository;
import 'support/fake_repositories.dart';

void main() {
  testWidgets(
    'chart amounts are readable without color or hover at 200 percent',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p = OverviewPresenter(
        PreviewRepository(),
        now: () => DateTime(2026, 9),
      );
      addTearDown(p.dispose);
      await p.setAccount(testAccount);
      final semantics = tester.ensureSemantics();
      for (final chart in [
        SpendingChart(presenter: p),
        TrendChart(presenter: p),
        DailyChart(presenter: p),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: chart,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final title = chart is SpendingChart
            ? 'View category amounts'
            : chart is TrendChart
            ? 'View monthly amounts'
            : 'View daily amounts';
        await tester.ensureVisible(find.text(title));
        await tester.pumpAndSettle();
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (chart is SpendingChart) {
          expect(find.text('Food: RM 352.80'), findsOneWidget);
        } else if (chart is TrendChart) {
          expect(
            find.text('2026-09: income RM 4,800.00; expenses RM 500.00'),
            findsOneWidget,
          );
        } else {
          expect(find.text('2026-09-02: RM 15.00'), findsOneWidget);
        }
      }
      semantics.dispose();
    },
  );

  testWidgets('dashboard and primary pages fit 200 percent phone text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      PocketwiseApp(presenters: testPresenters(PreviewRepository())),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final title in ['Transactions', 'Budgets', 'Reports', 'Settings']) {
      await tester.tap(find.text(title).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: title);
    }
  });

  testWidgets(
    'dashboard summaries distinguish unknown ratios, reserved cash and stale estimates',
    (tester) async {
      var helper = 0, wishlist = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardPlanSummary(
                currency: 'EUR',
                stale: true,
                openHelper: () => helper++,
                openWishlist: () => wishlist++,
                summary: {
                  'review': {
                    'debt_ratios': {
                      'effective_date': '2026-10-06',
                      'review_due': true,
                      'ratios': {
                        'dsr': {'value': '20.00'},
                        'dti': {'value': null},
                      },
                    },
                    'funding': {
                      'active_items': 2,
                      'active_target_total': 90000,
                      'active_funded_total': 50000,
                      'current_reserves': {'wishlist_reserved': 60000},
                      'as_of': '2026-10-06',
                      'usable': false,
                    },
                  },
                },
              ),
            ),
          ),
        ),
      );
      expect(find.text('DSR (net income): 20.00%'), findsOneWidget);
      expect(
        find.text('DTI (gross income): Needs updated information'),
        findsOneWidget,
      );
      expect(
        find.text('EUR 500.00 reserved toward EUR 900.00 in active targets'),
        findsOneWidget,
      );
      expect(find.text('Cash and plan need review.'), findsOneWidget);
      await tester.ensureVisible(find.text('Open financial helper'));
      await tester.tap(find.text('Open financial helper'));
      await tester.ensureVisible(find.text('Open guilt-free wishlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open guilt-free wishlist'));
      expect([helper, wishlist], [1, 1]);
    },
  );
}
