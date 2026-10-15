import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pocketwise/features/notifications/presenter/notification_presenter.dart';
import 'package:pocketwise/views/notification_settings_screen.dart';
import 'dart:async';
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/data/local_budget_alert_delivery.dart';
import 'package:pocketwise/data/local_bill_reminder_scheduler.dart';
import 'package:pocketwise/features/notifications/model/budget_alert_repository.dart';
import 'package:pocketwise/features/notifications/model/notification_repository.dart';
import 'package:pocketwise/features/notifications/presenter/budget_alert_presenter.dart';
import 'package:pocketwise/core/model/contracts.dart';
import 'support/fake_notifications.dart';
import 'support/fake_repositories.dart';
import 'bill_reminder_scheduler_test.dart' show DeviceNotifications;

BudgetAlertPlan plan({
  String owner = 'alex',
  String period = '2026-10',
  List<String> ids = const ['overall'],
}) => BudgetAlertPlan(
  ownerId: owner,
  ready: true,
  period: period,
  budgetIds: ids,
);

class Source implements BudgetAlertSource {
  BudgetAlertPlan value = plan();
  Completer<BudgetAlertPlan>? gate;
  bool fail = false;
  int loads = 0;
  @override
  Future<BudgetAlertPlan> load() async {
    loads++;
    if (fail) throw StateError('offline');
    return gate == null ? value : gate!.future;
  }
}

class Notifications extends DeviceNotifications {
  int shown = 0;
  final Set<int> visible = {};
  Completer<void>? gate;
  bool failShow = false;
  @override
  Future<void> cancel({required int id, String? tag}) async {
    visible.remove(id);
    await super.cancel(id: id, tag: tag);
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    expect(id, LocalBudgetAlertDelivery.notificationId);
    final target = jsonDecode(payload!) as Map;
    expect(target['type'], 'budget_review_v1');
    expect(target['ids'], isNotEmpty);
    expect(target.containsKey('spent'), isFalse);
    expect(
      notificationDetails!.android!.visibility,
      NotificationVisibility.private,
    );
    expect(body, isNot(contains('overall')));
    if (gate != null) await gate!.future;
    if (failShow) throw StateError('native failure');
    shown++;
    visible.add(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Notifications plugin;
  late LocalBudgetAlertDelivery delivery;
  late FakeNotifications prefs;
  late Source source;
  late BudgetAlertPresenter p;
  bool blocked = false;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterSecureStorage.setMockInitialValues({});
    plugin = Notifications();
    delivery = LocalBudgetAlertDelivery(
      const FlutterSecureStorage(),
      plugin: plugin,
    );
    prefs = FakeNotifications()
      ..preferences = const NotificationPreferences(
        enabled: true,
        budgets: true,
      )
      ..status = NotificationPermission.granted;
    source = Source();
    blocked = false;
    p = BudgetAlertPresenter(
      prefs,
      source,
      delivery,
      syncBlocked: () => blocked,
    );
  });
  tearDown(() {
    p.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'dedup survives refresh, dips, restart, toggle and logout; new month and budget alert',
    () async {
      await p.setAccount(testAccount);
      expect(plugin.shown, 1);
      await p.refresh();
      source.value = plan(ids: []);
      await p.refresh();
      source.value = plan();
      prefs.preferences = prefs.preferences.copy(budgets: false);
      await p.refresh();
      prefs.preferences = prefs.preferences.copy(budgets: true);
      await p.refresh();
      await p.endSession();
      final restarted = LocalBudgetAlertDelivery(
        const FlutterSecureStorage(),
        plugin: plugin,
      );
      await restarted.setOwner('alex');
      expect(await restarted.deliver(plan()), 0);
      expect(plugin.shown, 1);
      expect(await restarted.deliver(plan(ids: ['overall', 'food'])), 1);
      expect(await restarted.deliver(plan(period: '2026-11')), 1);
      expect(plugin.shown, 3);
      expect(plugin.settings!.iOS!.requestAlertPermission, isFalse);
    },
  );
  test(
    'denial, pending sync and failed fetch do not consume eligibility',
    () async {
      prefs.status = NotificationPermission.denied;
      await p.setAccount(testAccount);
      expect(source.loads, 0);
      prefs.status = NotificationPermission.granted;
      blocked = true;
      await p.refresh();
      expect(source.loads, 0);
      blocked = false;
      source.fail = true;
      await p.refresh();
      expect(p.state.error, isNotNull);
      expect(plugin.shown, 0);
      source.fail = false;
      await p.refresh();
      expect(plugin.shown, 1);
      expect(prefs.requests, 0);
    },
  );
  test('late response and mismatched owner cannot post after logout', () async {
    source.gate = Completer();
    final pending = p.setAccount(testAccount);
    await Future<void>.delayed(Duration.zero);
    await p.endSession();
    source.gate!.complete(plan());
    await pending;
    expect(plugin.shown, 0);
    source.gate = null;
    source.value = plan(owner: 'other');
    await p.setAccount(testAccount);
    expect(plugin.shown, 0);
    expect(p.state.error, isNotNull);
  });
  test('logout awaits native delivery then removes it', () async {
    plugin.gate = Completer();
    final opening = p.setAccount(testAccount);
    await Future<void>.delayed(Duration.zero);
    final logout = p.endSession();
    plugin.gate!.complete();
    await Future.wait([opening, logout]);
    expect(plugin.visible, isEmpty);
  });
  test('bill and budget cancellation stay isolated', () async {
    await p.setAccount(testAccount);
    final bills = LocalBillReminderScheduler(
      const FlutterSecureStorage(),
      plugin: plugin,
    );
    await bills.setOwner('alex');
    await bills.clear();
    await bills.replace([]);
    await bills.setOwner(null);
    expect(plugin.visible, {LocalBudgetAlertDelivery.notificationId});
    plugin.pending[42] = tz.TZDateTime.utc(2026, 11);
    await delivery.clear();
    expect(plugin.pending.keys, [42]);
  });
  test(
    'ambiguous native failure is not replayed; corrupt history fails closed',
    () async {
      plugin.failShow = true;
      await p.setAccount(testAccount);
      expect(p.state.error, isNotNull);
      plugin.failShow = false;
      await p.refresh();
      expect(plugin.shown, 0);
      await const FlutterSecureStorage().write(
        key: LocalBudgetAlertDelivery.historyKey,
        value: 'corrupt',
      );
      source.value = plan(ids: ['food']);
      await p.refresh();
      expect(p.state.error, isNotNull);
      expect(plugin.shown, 0);
    },
  );
  test(
    'app checks budget edits and preferences, and deletes local history with account',
    () async {
      final app = testPresenters(
        FakeRepositories()..account = testAccount,
        notificationRepository: prefs,
        budgetAlertSource: source,
        budgetAlertDelivery: delivery,
      );
      addTearDown(app.dispose);
      await app.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(plugin.shown, 1);
      source.value = plan(ids: ['food']);
      await app.budgets.save(
        BudgetDraft(period: '2026-10', limitAmount: 100, alertThreshold: 80),
      );
      await Future<void>.delayed(Duration.zero);
      expect(plugin.shown, 2);
      await app.notifications!.load();
      await app.notifications!.save(prefs.preferences.copy(budgets: false));
      expect(plugin.visible, isEmpty);
      expect(await app.auth.deleteAccount(), isTrue);
      expect(plugin.visible, isEmpty);
      expect(
        await const FlutterSecureStorage().read(
          key: LocalBudgetAlertDelivery.historyKey,
        ),
        '{}',
      );
    },
  );

  testWidgets('budget status and retry fit a phone at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = NotificationPresenter(prefs);
    addTearDown(settings.dispose);
    await tester.runAsync(() => p.setAccount(testAccount));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: NotificationSettingsScreen(presenter: settings, budgetAlerts: p),
      ),
    );
    await tester.pumpAndSettle();
    final check = find.text('Check budget alerts');
    await tester.scrollUntilVisible(check, 300);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Sent a budget alert for 1 budget'),
      findsOneWidget,
    );
    source.fail = true;
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(
      find.text('Could not check budget alerts. Connect and retry.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expect(prefs.requests, 0);
    debugDefaultTargetPlatformOverride = null;
  });

  test('unsupported targets never initialize the native plugin', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await delivery.setOwner('alex');
    expect(await delivery.deliver(plan()), 0);
    await delivery.clear();
    expect(plugin.settings, isNull);
  });
}
