import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/models/finance.dart';
import 'package:pocketwise/features/budgets/model/budget_review_repository.dart';
import 'package:pocketwise/features/budgets/presenter/budget_review_presenter.dart';
import 'package:pocketwise/features/notifications/presenter/notification_navigation_presenter.dart';
import 'package:pocketwise/views/budget_review_panel.dart';
import 'package:pocketwise/main.dart';
import 'support/fake_repositories.dart';

String payload({String owner = 'alex'}) => jsonEncode({
  'type': 'budget_review_v1',
  'owner': owner,
  'period': '2026-10',
  'ids': ['budget'],
});
Json reviewData() => {
  'owner_id': 'alex',
  'period': '2026-10',
  'currency': 'EUR',
  'as_of': '2026-10-15T00:00:00Z',
  'expires_at': '2099-01-01T00:00:00Z',
  'timezone': 'Asia/Kuala_Lumpur',
  'days_remaining': 17,
  'items': [
    {
      'id': 'budget',
      'period': '2026-10',
      'name': 'Overall monthly budget',
      'category_id': null,
      'limit_amount': 10000,
      'spent': 8000,
      'remaining': 2000,
      'daily_guide': 117,
      'threshold_reached': true,
      'alert_threshold': 80,
      'top_categories': [
        {'name': 'Food', 'amount': 8000},
      ],
    },
  ],
};

class ReviewRepository implements BudgetReviewRepository {
  Completer<Json>? gate;
  bool fail = false;
  int loads = 0;
  Json data = reviewData();
  @override
  Future<Json> load(String period) async {
    loads++;
    if (fail) throw StateError('offline');
    return gate == null ? data : gate!.future;
  }
}

void main() {
  test(
    'notification targets wait for auth and reject other owners and malformed data',
    () {
      final p = NotificationNavigationPresenter();
      addTearDown(p.dispose);
      p.open(payload());
      expect(p.state, isNull);
      p.setAccount(testAccount);
      expect(p.state!.ids, ['budget']);
      p.consume();
      p.open(payload(owner: 'someone-else'));
      expect(p.state, isNull);
      for (final value in [
        'bad',
        '{}',
        jsonEncode({
          'type': 'budget_review_v1',
          'owner': 'alex',
          'period': '2026-13',
          'ids': ['budget'],
        }),
      ]) {
        p.open(value);
        expect(p.state, isNull);
      }
      p.clear();
      p.open(payload());
      p.clear();
      p.setAccount(testAccount);
      expect(p.state, isNull);
    },
  );
  test(
    'review hides pending, expired and failed data and ignores late logout response',
    () async {
      final repo = ReviewRepository();
      var blocked = false;
      var now = DateTime.utc(2026, 10, 15);
      final p = BudgetReviewPresenter(
        repo,
        syncBlocked: () => blocked,
        now: () => now,
      );
      addTearDown(p.dispose);
      p.setAccount(testAccount);
      await p.open(BudgetReviewTarget('alex', '2026-10', ['budget']));
      expect(p.usable, isTrue);
      blocked = true;
      expect(p.usable, isFalse);
      await p.refresh();
      expect(repo.loads, 1);
      blocked = false;
      await p.refresh();
      now = DateTime.utc(2100);
      expect(p.usable, isFalse);
      repo.fail = true;
      await p.refresh();
      expect(p.state.data, isNull);
      repo.fail = false;
      repo.gate = Completer();
      final pending = p.refresh();
      p.setAccount(null);
      repo.gate!.complete(reviewData());
      await pending;
      expect(p.state.data, isNull);
    },
  );
  testWidgets(
    'review details and actions fit at 200 percent; missing budgets and errors are clear',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = ReviewRepository();
      final p = BudgetReviewPresenter(repo);
      addTearDown(p.dispose);
      p.setAccount(testAccount);
      await p.open(
        BudgetReviewTarget('alex', '2026-10', ['budget', 'removed']),
      );
      var edits = 0, transactions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: BudgetReviewPanel(
                  presenter: p,
                  close: () {},
                  adjust: (_) async {
                    edits++;
                  },
                  transactions: (_) async {
                    transactions++;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('17 days left'), findsOneWidget);
      expect(
        find.textContaining('Some budgets from this alert'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(find.text('Review transactions'), 300);
      await tester.tap(find.text('Review transactions'));
      await tester.scrollUntilVisible(find.text('Adjust limit'), 200);
      await tester.tap(find.text('Adjust limit'));
      await tester.pumpAndSettle();
      expect(edits, 1);
      expect(transactions, 1);
      expect(repo.loads, 2);
      repo.fail = true;
      await p.refresh();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not load a fresh budget review'),
        findsOneWidget,
      );
      expect(find.text('Adjust limit'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'notification opens budget review and routes its transactions to the correct month',
    (tester) async {
      final repo = ReviewRepository();
      final app = testPresenters(
        FakeRepositories()..account = testAccount,
        budgetReviewRepository: repo,
      );
      await tester.pumpWidget(PocketwiseApp(presenters: app));
      await tester.pumpAndSettle();
      app.notificationNavigation.open(payload());
      expect(app.notificationNavigation.state, isNotNull);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(repo.loads, 1);
      expect(find.text('Budget review · 2026-10'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Review transactions'), 200);
      await tester.tap(find.text('Review transactions'));
      await tester.pumpAndSettle();
      expect(app.history.state.filter.start, DateTime(2026, 10));
      expect(app.history.state.filter.type, 'expense');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
