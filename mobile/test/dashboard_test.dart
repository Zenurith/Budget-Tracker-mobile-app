import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/core/model/contracts.dart';
import 'support/fake_repositories.dart';
import 'package:pocketwise/main.dart';
import 'package:pocketwise/models/finance.dart';

class PreviewRepository extends FakeRepositories {
  PreviewRepository() {
    account = testAccount;
    final categories = [
      FinanceCategory.fromJson({
        'id': 'food',
        'name': 'Food',
        'type': 'expense',
        'icon': 'restaurant',
        'color': '#E3A25F',
      }),
      FinanceCategory.fromJson({
        'id': 'transport',
        'name': 'Transport',
        'type': 'expense',
        'icon': 'directions_car',
        'color': '#6D9DC5',
      }),
      FinanceCategory.fromJson({
        'id': 'salary',
        'name': 'Salary',
        'type': 'income',
        'icon': 'work',
        'color': '#4D8B70',
      }),
    ];
    final summary = {
      'balance': 434720,
      'income': 480000,
      'expenses': 45280,
      'net': 434720,
      'category_breakdown': {'food': 35280, 'transport': 10000},
      'daily_expenses': {'2026-09-02': 1500, '2026-09-10': 2400},
      'trend': List.generate(
        6,
        (i) => {
          'month': '2026-0${i + 4}',
          'income': 480000,
          'expense': 25000 + i * 5000,
        },
      ),
    };
    final budgets = [
      {
        'id': 'overall',
        'category_id': null,
        'limit_amount': 200000,
        'spent': 45280,
        'alert_threshold': 80,
      },
      {
        'id': 'food',
        'category_id': 'food',
        'limit_amount': 60000,
        'spent': 35280,
        'alert_threshold': 80,
      },
    ];
    final entries = [
      Entry.fromJson({
        'id': 'one',
        'amount': 2450,
        'type': 'expense',
        'category_id': 'food',
        'date': '2026-09-28',
        'note': 'Lunch at the little café',
      }),
      Entry.fromJson({
        'id': 'two',
        'amount': 1800,
        'type': 'expense',
        'category_id': 'transport',
        'date': '2026-09-27',
        'note': 'Grab ride home',
      }),
    ];
    snapshot = MonthlySnapshot(
      summary: summary,
      categories: categories,
      budgets: budgets,
      entries: entries,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('PocketwiseSans');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final size in [const Size(1440, 1100), const Size(390, 844)]) {
    final label = size.width > 1000 ? 'desktop' : 'phone';
    testWidgets('dashboard and navigation fit $label', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        PocketwiseApp(presenters: testPresenters(PreviewRepository())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Your money, at a glance.'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/${Platform.isWindows ? 'windows/' : ''}dashboard_$label.png',
        ),
      );
      for (final title in ['Transactions', 'Budgets', 'Reports', 'Settings']) {
        await tester.tap(find.text(title).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$title on $label');
      }
    });
  }
}
