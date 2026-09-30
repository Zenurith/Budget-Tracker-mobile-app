import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/core/model/contracts.dart';
import 'package:pocketwise/main.dart';
import 'package:pocketwise/views/transaction_filters.dart';
import 'support/fake_repositories.dart';

void main() {
  testWidgets('category editor sends selected icon and color', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeRepositories()..account = testAccount;
    await tester.pumpWidget(PocketwiseApp(presenters: testPresenters(repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add category'));
    await tester.tap(find.text('Add category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Books');
    final icon = find.byType(DropdownButtonFormField<String>).at(1);
    await tester.ensureVisible(icon);
    await tester.tap(icon);
    await tester.pumpAndSettle();
    await tester.tap(find.text('movie').last);
    await tester.pumpAndSettle();
    final color = find.byType(DropdownButtonFormField<String>).at(2);
    await tester.ensureVisible(color);
    await tester.tap(color);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Purple').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.savedCategory!.icon, 'movie');
    expect(repo.savedCategory!.color, '#AC8FC0');
    expect(repo.savedCategory!.name, 'Books');
    expect(tester.takeException(), isNull);
  });

  testWidgets('transaction amount filters reach repository and clear', (
    tester,
  ) async {
    final repo = FakeRepositories()..account = testAccount;
    await tester.pumpWidget(PocketwiseApp(presenters: testPresenters(repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transactions').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Date & amount'));
    await tester.tap(find.text('Date & amount'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '0');
    await tester.enterText(find.byType(TextFormField).at(1), '12.34');
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(repo.lastFilter!.minAmount, 0);
    expect(repo.lastFilter!.maxAmount, 1234);
    await tester.ensureVisible(find.text('Clear filters'));
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(repo.lastFilter!.minAmount, isNull);
    expect(repo.lastFilter!.maxAmount, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter dialog validates ranges at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: TransactionFilters(
            filter: EntryFilter(
              start: DateTime(2026, 8, 31),
              end: DateTime(2026, 9, 30),
            ),
            currency: 'MYR',
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(0), '20');
    await tester.enterText(find.byType(TextFormField).at(1), '10');
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(find.text('Minimum must not exceed maximum.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
