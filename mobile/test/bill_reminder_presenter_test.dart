import 'dart:async';
import 'package:test/test.dart';
import 'package:pocketwise/features/notifications/model/bill_reminder_repository.dart';
import 'package:pocketwise/features/notifications/model/notification_repository.dart';
import 'package:pocketwise/features/notifications/presenter/bill_reminder_presenter.dart';
import 'package:pocketwise/features/auth/presenter/auth_presenter.dart';
import 'support/fake_notifications.dart';
import 'support/fake_bill_reminders.dart';
import 'support/fake_repositories.dart';

void main() {
  late FakeNotifications preferences;
  late FakeBillSource source;
  late FakeBillScheduler scheduler;
  late BillReminderPresenter p;
  setUp(() {
    preferences = FakeNotifications()
      ..preferences = const NotificationPreferences(
        enabled: true,
        bills: true,
        billLeadDays: 3,
      )
      ..status = NotificationPermission.granted;
    source = FakeBillSource();
    scheduler = FakeBillScheduler();
    p = BillReminderPresenter(preferences, source, scheduler);
  });
  tearDown(() => p.dispose());

  test(
    'app composition refreshes after bill changes and preference saves, then clears on logout',
    () async {
      final app = testPresenters(
        FakeRepositories()..account = testAccount,
        notificationRepository: preferences,
        billReminderSource: source,
        billReminderScheduler: scheduler,
      );
      addTearDown(app.dispose);
      await app.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(scheduler.pending, hasLength(1));
      final before = source.loads;
      source.plan = BillReminderPlan(ownerId: 'alex', ready: true, items: []);
      await app.planning.saveSchedule('commitments', {'name': 'Changed bill'});
      await Future<void>.delayed(Duration.zero);
      expect(source.loads, greaterThan(before));
      expect(scheduler.pending, isEmpty);
      source.plan = reminderPlan();
      await app.notifications!.load();
      expect(scheduler.pending, hasLength(1));
      await app.notifications!.save(preferences.preferences.copy(bills: false));
      expect(scheduler.pending, isEmpty);
      await app.notifications!.save(preferences.preferences.copy(bills: true));
      expect(scheduler.pending, hasLength(1));
      expect(await app.auth.logout(), isTrue);
      expect(scheduler.pending, isEmpty);
      expect(scheduler.owner, isNull);
    },
  );

  test(
    'permissions and preferences govern scheduling without prompting',
    () async {
      await p.setAccount(testAccount);
      expect(p.state.count, 1);
      expect(source.lead, 3);
      expect(preferences.requests, 0);
      preferences.preferences = preferences.preferences.copy(enabled: false);
      await p.refresh(invalidate: true);
      expect(scheduler.pending, isEmpty);
      preferences.preferences = preferences.preferences.copy(enabled: true);
      preferences.status = NotificationPermission.blocked;
      await p.refresh();
      expect(scheduler.pending, isEmpty);
      expect(source.loads, 1);
      preferences.status = NotificationPermission.provisional;
      await p.refresh();
      expect(scheduler.pending, hasLength(1));
    },
  );
  test(
    'ordinary network failure preserves schedule; a mutation cancels before fetching',
    () async {
      await p.setAccount(testAccount);
      source.fail = true;
      await p.refresh();
      expect(scheduler.pending, hasLength(1));
      expect(p.state.error, isNotNull);
      final mutation = p.refresh(invalidate: true);
      final newerRefresh = p.refresh();
      await Future.wait([mutation, newerRefresh]);
      expect(scheduler.pending, isEmpty);
      expect(p.state.error, isNotNull);
    },
  );
  test('late network responses cannot reschedule after logout', () async {
    await p.setAccount(testAccount);
    source.gate = Completer<BillReminderPlan>();
    final loading = p.refresh();
    await Future<void>.delayed(Duration.zero);
    await p.endSession();
    source.gate!.complete(reminderPlan());
    await loading;
    expect(scheduler.owner, isNull);
    expect(scheduler.pending, isEmpty);
  });
  test('logout awaits native scheduling and cancels its result', () async {
    await p.setAccount(testAccount);
    scheduler.replaceGate = Completer<void>();
    final refreshing = p.refresh();
    await Future<void>.delayed(Duration.zero);
    var ended = false;
    final logout = p.endSession().then((_) => ended = true);
    await Future<void>.delayed(Duration.zero);
    expect(ended, isFalse);
    scheduler.replaceGate!.complete();
    await Future.wait([refreshing, logout]);
    expect(scheduler.pending, isEmpty);
    expect(scheduler.owner, isNull);
  });
  test('a mismatched server owner is never scheduled', () async {
    source.plan = reminderPlan('someone-else');
    await p.setAccount(testAccount);
    expect(scheduler.replacements, 0);
    expect(p.state.error, isNotNull);
  });
  test(
    'logout failure leaves account signed in and does not silently retain alerts',
    () async {
      final repo = FakeRepositories()..account = testAccount;
      final auth = AuthPresenter(repo)..beforeSessionEnd = p.endSession;
      addTearDown(auth.dispose);
      await auth.initialize();
      await p.setAccount(testAccount);
      scheduler.failClear = true;
      expect(await auth.logout(), isFalse);
      expect(auth.state.account, testAccount);
      expect(repo.account, testAccount);
      scheduler.failClear = false;
      expect(await auth.logout(), isTrue);
      expect(scheduler.pending, isEmpty);
      expect(auth.state.account, isNull);
    },
  );
}
