import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/features/notifications/model/notification_repository.dart';
import 'package:pocketwise/features/notifications/presenter/notification_presenter.dart';
import 'package:pocketwise/views/notification_settings_screen.dart';
import 'support/fake_notifications.dart';
import 'support/fake_repositories.dart';
import 'package:pocketwise/main.dart';

void main() {
  testWidgets('settings opens notifications without requesting permission', (
    tester,
  ) async {
    final repo = FakeNotifications();
    final app = testPresenters(
      FakeRepositories()..account = testAccount,
      notificationRepository: repo,
    );
    await tester.pumpWidget(PocketwiseApp(presenters: app));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Notifications'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Permission not requested'), findsOneWidget);
    expect(repo.requests, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'permission is explicit and returning from settings refreshes without prompting',
    (tester) async {
      final repo = FakeNotifications();
      final p = NotificationPresenter(repo);
      addTearDown(p.dispose);
      await tester.pumpWidget(
        MaterialApp(home: NotificationSettingsScreen(presenter: p)),
      );
      await tester.pumpAndSettle();
      expect(repo.requests, 0);
      expect(find.text('Permission not requested'), findsOneWidget);
      repo.status = NotificationPermission.denied;
      await tester.tap(find.text('Allow notifications'));
      await tester.pumpAndSettle();
      expect(repo.requests, 1);
      expect(find.text('Permission not allowed'), findsOneWidget);
      await tester.tap(find.text('Open system settings'));
      await tester.pumpAndSettle();
      expect(repo.settings, 1);
      repo.status = NotificationPermission.granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Device permission allowed'), findsOneWidget);
      expect(repo.requests, 1);
    },
  );
  testWidgets(
    'preferences fit a phone at 200 percent and save without prompting',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeNotifications();
      final p = NotificationPresenter(repo);
      addTearDown(p.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: NotificationSettingsScreen(presenter: p),
        ),
      );
      await tester.pumpAndSettle();
      for (final title in [
        'Use notifications',
        'Bill reminders',
        'Budget alerts',
        'Cash review reminders',
      ]) {
        final toggle = find.widgetWithText(SwitchListTile, title);
        await tester.scrollUntilVisible(toggle, 250);
        await tester.pumpAndSettle();
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      }
      expect(repo.preferences.enabled, isTrue);
      expect(repo.preferences.bills, isTrue);
      expect(repo.preferences.budgets, isTrue);
      expect(repo.preferences.cashReview, isTrue);
      expect(repo.requests, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('unsupported devices have no permission request button', (
    tester,
  ) async {
    final repo = FakeNotifications()
      ..status = NotificationPermission.unsupported;
    final p = NotificationPresenter(repo);
    addTearDown(p.dispose);
    await tester.pumpWidget(
      MaterialApp(home: NotificationSettingsScreen(presenter: p)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Allow notifications'), findsNothing);
    expect(find.text('Open system settings'), findsNothing);
    expect(repo.requests, 0);
  });
}
