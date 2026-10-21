import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/features/forecast/model/forecast_repository.dart';
import 'package:pocketwise/features/forecast/presenter/forecast_presenter.dart';
import 'package:pocketwise/models/finance.dart';
import 'package:pocketwise/views/cash_forecast_screen.dart';
import 'support/fake_repositories.dart';

class Repo implements ForecastRepository {
  Json? request;
  @override
  Future<Json> calculate(Json assumptions) async {
    request = assumptions;
    return {
      'ready': false,
      'as_of': '2026-10-21',
      'end': '2026-11-19',
      'timezone': 'UTC',
      'reasons': ['Review cash'],
    };
  }
}

void main() {
  testWidgets(
    'multiple event rows submit labels and amounts and can be removed',
    (tester) async {
      final repo = Repo();
      final p = ForecastPresenter(repo, syncBlocked: () => false)
        ..setAccount(testAccount);
      await tester.pumpWidget(
        MaterialApp(
          home: CashForecastScreen(presenter: p, currency: 'MYR'),
        ),
      );
      await tester.enterText(find.byType(TextFormField).at(0), '0');
      await tester.enterText(find.byType(TextFormField).at(1), '100');
      for (final kind in ['income', 'expense']) {
        await tester.ensureVisible(find.text('Add $kind'));
        await tester.tap(find.text('Add $kind'));
        await tester.pumpAndSettle();
        final fields = find.byType(TextFormField);
        final offset = kind == 'income' ? 2 : 5;
        for (var i = 0; i < 3; i++) {
          await tester.ensureVisible(fields.at(offset + i));
          await tester.enterText(
            fields.at(offset + i),
            [kind, '2026-10-22', '50'][i],
          );
        }
      }
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Calculate forecast'));
      await tester.tap(find.text('Calculate forecast'));
      await tester.pumpAndSettle();
      expect((repo.request!['events'] as List).length, 2);
      expect(repo.request!['events'][1]['amount'], 5000);
      expect(repo.request!.containsKey('income_date'), false);
      await tester.ensureVisible(find.text('Remove event').last);
      await tester.tap(find.text('Remove event').last);
      await tester.pumpAndSettle();
      expect(find.text('Remove event'), findsOneWidget);
      expect(p.state.result, isEmpty);
      await tester.pumpWidget(const SizedBox());
      p.dispose();
    },
  );
}
