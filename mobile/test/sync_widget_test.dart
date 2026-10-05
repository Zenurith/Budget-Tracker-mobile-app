import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/features/sync/model/sync_repository.dart';
import 'package:pocketwise/features/sync/presenter/sync_presenter.dart';
import 'package:pocketwise/views/sync_screen.dart';
import 'support/fake_sync_repository.dart';

void main() {
  testWidgets(
    'conflict comparison and confirmation fit a phone at 200 percent',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final entry = {
        'amount': 100,
        'type': 'expense',
        'category_id': 'food',
        'date': '2026-10-05',
        'note': 'Lunch',
        'payment_method': 'Cash',
      };
      final repo = FakeSyncRepository()
        ..state = SyncState(
          operations: [
            {
              'request': {
                'operation_id': 'one',
                'action': 'update',
                'transaction_id': 'entry',
                'transaction': entry,
              },
              'created_at': '2026-10-05',
              'status': 'conflict',
              'reviewed': true,
              'server': {...entry, 'amount': 200},
            },
          ],
        );
      final p = SyncPresenter(repo);
      addTearDown(p.dispose);
      addTearDown(repo.controller.close);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SyncScreen(presenter: p, currency: 'EUR'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Use my change'), 300);
    await tester.ensureVisible(find.text('Use my change'));
    await tester.pumpAndSettle();
      await tester.tap(find.text('Use my change'));
      await tester.pumpAndSettle();
      expect(repo.resolved, isNull);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(repo.resolved, 'one');
      expect(repo.keptLocal, true);
      expect(find.text('No pending changes.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
