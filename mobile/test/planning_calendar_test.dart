import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/features/planning/presenter/planning_presenter.dart';
import 'package:pocketwise/views/planning_calendar.dart';

void main() {
  testWidgets(
    'calendar filters days, resets on month change and shows payday',
    (tester) async {
      Future<void> show(int month) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanningCalendar(
                state: PlanningState(
                  month: DateTime(2028, month),
                  data: {
                    'as_of': '2028-02-20',
                    'next_income_date': '2028-02-29',
                    'occurrences': [
                      {
                        'due_date': '2028-02-10',
                        'name': 'Rent',
                        'overdue': true,
                      },
                      {
                        'due_date': '2028-02-29',
                        'name': 'Loan',
                        'overdue': false,
                      },
                    ],
                  },
                ),
                occurrenceBuilder: (due) => Text(due['name'] as String),
              ),
            ),
          ),
        ),
      );
      await show(2);
      expect(find.text('1 overdue in this month'), findsOneWidget);
      await tester.tap(find.text('29'));
      await tester.pump();
      expect(find.text('Loan'), findsOneWidget);
      expect(find.text('Rent'), findsNothing);
      expect(find.textContaining('Confirmed next payday.'), findsOneWidget);
      await tester.tap(find.text('Show whole month'));
      await tester.pump();
      expect(find.text('Rent'), findsOneWidget);
      await tester.ensureVisible(find.text('1'));
      await tester.tap(find.text('1'));
      await tester.pump();
      expect(
        find.text('No scheduled obligations on this day.'),
        findsOneWidget,
      );
      await show(3);
      expect(find.text('Show whole month'), findsNothing);
      expect(find.textContaining('No confirmed payday'), findsOneWidget);
    },
  );

  testWidgets(
    'narrow calendar supports large text and disables stale selection',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: PlanningCalendar(
                  state: PlanningState(
                    month: DateTime(2026, 10),
                    error: 'Offline',
                  ),
                  occurrenceBuilder: (_) => const SizedBox(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('1'));
      await tester.tap(find.text('1'));
      await tester.pump();
      expect(find.text('Show whole month'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
