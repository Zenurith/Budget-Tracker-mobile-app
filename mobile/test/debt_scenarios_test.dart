import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/features/debt_planner/model/scenario_repository.dart';
import 'package:pocketwise/features/debt_planner/presenter/scenario_presenter.dart';
import 'package:pocketwise/models/finance.dart';
import 'package:pocketwise/views/debt_planner_screen.dart';
import 'support/fake_repositories.dart';

class Repo implements ScenarioRepository {
  final calls = <Json>[];
  Completer<Json>? pending;
  @override
  Future<Json> load() async => pending == null
      ? {
          'as_of': '2026-10-21',
          'currency': 'MYR',
          'scenarios': [],
          'debts': [
            {'name': 'Car', 'balance': 100000, 'rate': null, 'minimum': 10000},
          ],
        }
      : pending!.future;
  @override
  Future<Json> save(Json draft) async {
    calls.add(draft);
    return draft;
  }

  @override
  Future<void> delete(String id) async {}
}

void main() {
  test('same save retries reuse key and logout drops late data', () async {
    final repo = Repo();
    final p = ScenarioPresenter(repo)..setAccount(testAccount);
    await p.save({'name': 'Test'});
    await p.save({'name': 'Test'});
    expect(repo.calls[0]['operation_id'], repo.calls[1]['operation_id']);
    repo.pending = Completer<Json>();
    final loading = p.reload();
    p.setAccount(null);
    repo.pending!.complete({
      'scenarios': [
        {'name': 'Private'},
      ],
    });
    await loading;
    expect(p.state.data, isEmpty);
    p.dispose();
  });
  testWidgets('import prefills known amounts but leaves interest unknown', (
    tester,
  ) async {
    final p = ScenarioPresenter(Repo())..setAccount(testAccount);
    await tester.pumpWidget(
      MaterialApp(
        home: DebtPlannerScreen(currency: 'MYR', presenter: p),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Import saved debts'));
    await tester.tap(find.text('Import saved debts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace inputs'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Car'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '1000.00'), findsOneWidget);
    final rate = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Annual interest rate (%)'),
    );
    expect(rate.controller!.text, isEmpty);
    p.setAccount(null);
    await tester.pump();
    expect(find.widgetWithText(TextFormField, 'Car'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    p.dispose();
  });
}
