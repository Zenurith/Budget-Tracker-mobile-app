import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/features/funding/presenter/funding_presenter.dart';
import 'package:pocketwise/views/wishlist_screen.dart';
import 'support/fake_repositories.dart';

Map<String, dynamic> wish() => {
  'id': 'camera',
  'name': 'Camera',
  'target_cost': 50000,
  'funded_amount': 50000,
  'priority': 1,
  'status': 'active',
  'monthly_contribution': 0,
  'remaining_target': 0,
  'readiness': 'Ready under your plan',
  'reasons': [],
  'quote': 'current-quote',
};
FakeFundingRepository repository() => FakeFundingRepository()
  ..data.addAll({
    'wishlist': [wish()],
    'purchases': [],
    'wishlist_reserved': 50000,
    'usable': true,
    'can_allocate': true,
    'free_to_allocate': 70000,
    'coverage_shortfall': 0,
    'missing_inputs': [],
    'snapshot_token': 'snapshot',
    'snapshot': {
      'as_of': '2026-10-01',
      'accounts': [
        {'name': 'Cash', 'amount': 400000},
      ],
    },
    'categories': [
      {'id': 'shopping', 'name': 'Shopping', 'type': 'expense'},
      {'id': 'income', 'name': 'Refunds', 'type': 'income'},
    ],
  });

void main() {
  testWidgets('item creation confirms cost without creating a reservation', (
    tester,
  ) async {
    final repo = repository();
    final p = FundingPresenter(repo)..setAccount(testAccount);
    addTearDown(p.dispose);
    await p.reload();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WishlistEditor(presenter: p, mode: 'item'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Item name'),
      'Headphones',
    );
    await tester.enterText(
      find.widgetWithText(
        TextFormField,
        'Total cost (MYR), including tax and shipping',
      ),
      '499.95',
    );
    final confirmation = find.text(
      'I reviewed the total cost and forecast; paused funds remain reserved',
    );
    await tester.ensureVisible(confirmation);
    await tester.tap(confirmation);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(repo.lastWishlist!['target_cost'], 49995);
    expect(repo.lastWishlist!['monthly_contribution'], 0);
    expect(repo.moves, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'purchase confirmation sends prior cash quote and selected account',
    (tester) async {
      final repo = repository();
      final p = FundingPresenter(repo)..setAccount(testAccount);
      addTearDown(p.dispose);
      await p.reload();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WishlistEditor(presenter: p, mode: 'purchase', item: wish()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Account used'));
      await tester.tap(find.text('Account used'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Cash ·').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Category'));
      await tester.tap(find.text('Category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shopping').last);
      await tester.pumpAndSettle();
      final confirmation = find.text(
        'I confirm this purchase happened and is the only payment missing from the reviewed cash balance',
      );
      await tester.ensureVisible(confirmation);
      await tester.tap(confirmation);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(repo.lastPurchase!['quote'], 'current-quote');
      expect(repo.lastPurchase!['account_name'], 'Cash');
      expect(
        repo.lastPurchase!['baseline_effect'],
        'subtract_from_prior_snapshot',
      );
      expect(repo.lastPurchase!['amount'], 50000);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('phone at 200 percent shows readiness and release flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = repository();
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
        home: WishlistScreen(presenter: p),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Release cash'), 400);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Release cash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Release cash'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (MYR)'),
      '10',
    );
    await tester.ensureVisible(find.text('I confirm this reservation change'));
    await tester.tap(find.text('I confirm this reservation change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(repo.lastMove!['amount'], 1000);
    expect(repo.lastMove!['source_id'], 'camera');
    expect(tester.takeException(), isNull);
  });
}
