import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/core/model/contracts.dart';
import 'package:pocketwise/features/overview/presenter/overview_presenter.dart';
import 'package:pocketwise/features/sync/model/sync_repository.dart';
import 'package:pocketwise/features/sync/presenter/sync_presenter.dart';
import 'package:pocketwise/models/finance.dart';
import 'package:pocketwise/views/dashboard_cash_card.dart';
import 'package:pocketwise/views/setup_screen.dart';
import 'support/fake_repositories.dart';
import 'support/fake_sync_repository.dart';

Json projection({bool payday = true}) => {
  'setup': {
    'complete': false,
    'budget_month': '2026-10',
    'steps': [
      for (final id in [
        'cash',
        'income',
        'commitments',
        'budget',
        'savings',
        'review',
      ])
        {'id': id, 'done': id == 'cash', 'optional': id == 'savings'},
    ],
  },
  'availability': {
    'usable': true,
    'free_to_allocate': 160000,
    'coverage_shortfall': 0,
    'next_income_date': payday ? '2026-10-20' : null,
    'horizon_end': payday ? '2026-10-20' : '2026-11-11',
    'cash_reviewed_at': '2026-10-13T08:00:00Z',
    'plan_reviewed_at': '2026-10-13T08:00:00Z',
    'expires_at': '2026-10-14T00:00:00Z',
    'liquid_total': 400000,
    'scheduled_obligations': 0,
    'essential_allowances': 120000,
    'required_savings': 0,
    'emergency_reserved': 100000,
    'savings_reserved': 0,
    'wishlist_reserved': 0,
    'buffer_amount': 20000,
  },
};

void main() {
  test(
    'availability rejects expired, cached, failed, loading and unsynced results',
    () async {
      var now = DateTime.utc(2026, 10, 13, 9);
      final repo = FakeRepositories()
        ..snapshot = MonthlySnapshot(summary: {'dashboard': projection()});
      final p = OverviewPresenter(repo, now: () => now);
      addTearDown(p.dispose);
      await p.setAccount(testAccount);
      expect(p.availabilityUsable(), isTrue);
      expect(p.availabilityUsable(syncBlocked: true), isFalse);
      now = DateTime.utc(2026, 10, 14);
      expect(p.availabilityUsable(), isFalse);
      now = DateTime.utc(2026, 10, 13, 9);
      final gate = Completer<MonthlySnapshot>();
      repo.onLoad = (_) => gate.future;
      final pending = p.reload();
      expect(p.availabilityUsable(), isFalse);
      gate.completeError(StateError('Offline'));
      await pending;
      expect(p.availabilityUsable(), isFalse);
      repo.onLoad = null;
      repo.snapshot = MonthlySnapshot(
        summary: {'dashboard': projection()},
        cachedAt: now.toIso8601String(),
      );
      await p.reload();
      expect(p.availabilityUsable(), isFalse);
      await p.setAccount(null);
      expect(p.availability, isEmpty);
    },
  );

  testWidgets(
    'cash card fits large text, explains protection and hides pending amounts',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeRepositories()
        ..snapshot = MonthlySnapshot(summary: {'dashboard': projection()});
      final p = OverviewPresenter(
        repo,
        now: () => DateTime.utc(2026, 10, 13, 9),
      );
      final syncRepo = FakeSyncRepository();
      final sync = SyncPresenter(syncRepo);
      addTearDown(p.dispose);
      addTearDown(sync.dispose);
      addTearDown(syncRepo.controller.close);
      await p.setAccount(testAccount);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: DashboardCashCard(
                    presenter: p,
                    sync: sync,
                    openFunding: () {},
                    openSetup: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Available until payday'), findsOneWidget);
      expect(find.text('RM 1,600.00'), findsOneWidget);
      await tester.ensureVisible(find.text('See the breakdown'));
      await tester.tap(find.text('See the breakdown'));
      await tester.pumpAndSettle();
      expect(find.text('Emergency savings reserved'), findsOneWidget);
      expect(tester.takeException(), isNull);
      syncRepo.controller.add(
        SyncState(
          operations: [
            {'id': 'pending'},
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('RM 1,600.00'), findsNothing);
      expect(find.text('Needs review'), findsOneWidget);
      repo.snapshot = MonthlySnapshot(
        summary: {'dashboard': projection(payday: false)},
      );
      await p.reload();
      await tester.pumpAndSettle();
      expect(find.text('Available for the next 30 days'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'setup resumes saved progress and opens the current month budget',
    (tester) async {
      final repo = FakeRepositories()
        ..account = testAccount
        ..snapshot = MonthlySnapshot(summary: {'dashboard': projection()});
      final app = testPresenters(repo);
      addTearDown(app.dispose);
      await app.initialize();
      String? budgetMonth;
      await tester.pumpWidget(
        MaterialApp(
          home: SetupScreen(
            presenters: app,
            editBudget: (month) async {
              budgetMonth = month;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 of 5 required steps complete'), findsOneWidget);
      final budgetCard = find.ancestor(
        of: find.text('Set this month’s budget'),
        matching: find.byType(Card),
      );
      final button = find.descendant(
        of: budgetCard,
        matching: find.text('Continue step'),
      );
    await tester.scrollUntilVisible(button, 250);
      await tester.pumpAndSettle();
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(budgetMonth, '2026-10');
      expect(app.overview.period, '2026-09');
      expect(repo.saves, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
