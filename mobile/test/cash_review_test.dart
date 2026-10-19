import 'package:pocketwise/features/notifications/presenter/notification_navigation_presenter.dart';
import 'package:pocketwise/main.dart';
import 'package:pocketwise/views/funding_screen.dart';
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
import 'package:pocketwise/data/local_cash_review_delivery.dart';
import 'package:pocketwise/data/local_bill_reminder_scheduler.dart';
import 'package:pocketwise/features/notifications/model/cash_review_repository.dart';
import 'package:pocketwise/features/notifications/model/notification_repository.dart';
import 'package:pocketwise/features/notifications/presenter/cash_review_presenter.dart';
import 'package:pocketwise/core/model/contracts.dart';
import 'support/fake_notifications.dart';
import 'support/fake_repositories.dart';
import 'bill_reminder_scheduler_test.dart' show DeviceNotifications;

CashReviewPlan plan({
  String owner = 'alex',
  String day = '2026-10-19',
  bool needsReview = true,
}) => CashReviewPlan(
  ownerId: owner,
  day: day,
  needsReview: needsReview,
  reason: 'Cash review status',
);

class Source implements CashReviewSource {
  CashReviewPlan value = plan();
  Completer<CashReviewPlan>? gate;
  bool fail = false;
  int loads = 0;
  @override
  Future<CashReviewPlan> load() async {
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
    expect(id, LocalCashReviewDelivery.notificationId);
    final target = jsonDecode(payload!) as Map;
    expect(target['type'], 'cash_review_v1');
    expect(target['owner'], 'alex');
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
  late LocalCashReviewDelivery delivery;
  late FakeNotifications prefs;
  late Source source;
  late CashReviewPresenter p;
  bool blocked = false;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterSecureStorage.setMockInitialValues({});
    plugin = Notifications();
    delivery = LocalCashReviewDelivery(
      const FlutterSecureStorage(),
      plugin: plugin,
    );
    prefs = FakeNotifications()
      ..preferences = const NotificationPreferences(
        enabled: true,
        cashReview: true,
      )
      ..status = NotificationPermission.granted;
    source = Source();
    blocked = false;
    p = CashReviewPresenter(
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
  test('cash-review taps wait for auth and reject another owner', () {
    final navigation = NotificationNavigationPresenter();
    addTearDown(navigation.dispose);
    String payload(String owner) =>
        jsonEncode({'type': 'cash_review_v1', 'owner': owner});
    navigation.open(payload('alex'));
    expect(navigation.cashReview.state, isNull);
    navigation.setAccount(testAccount);
    expect(navigation.cashReview.state, 'alex');
    expect(navigation.state, isNull);
    navigation.cashReview.consume();
    navigation.open(payload('other'));
    expect(navigation.cashReview.state, isNull);
    navigation.open('{invalid');
    navigation.open(payload('alex'));
    navigation.clear();
    expect(navigation.cashReview.state, isNull);
    navigation.setAccount(testAccount);
    expect(navigation.cashReview.state, isNull);
  });

  testWidgets('cash-review notification opens fresh protected funding', (
    tester,
  ) async {
    final app = testPresenters(FakeRepositories()..account = testAccount);
    await tester.pumpWidget(PocketwiseApp(presenters: app));
    await tester.pumpAndSettle();
    app.notificationNavigation.open(
      jsonEncode({'type': 'cash_review_v1', 'owner': 'alex'}),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(FundingScreen), findsOneWidget);
    expect(app.funding.state.data, isNotEmpty);
    expect(app.notificationNavigation.cashReview.state, isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'dedup survives review, restart, toggle and logout; next local day can alert',
    () async {
      await p.setAccount(testAccount);
      expect(plugin.shown, 1);
      await p.refresh();
      source.value = plan(needsReview: false);
      await p.refresh();
      source.value = plan();
      prefs.preferences = prefs.preferences.copy(cashReview: false);
      await p.refresh();
      prefs.preferences = prefs.preferences.copy(cashReview: true);
      await p.refresh();
      await p.endSession();
      final restarted = LocalCashReviewDelivery(
        const FlutterSecureStorage(),
        plugin: plugin,
      );
      await restarted.setOwner('alex');
      expect(await restarted.deliver(plan()), 0);
      expect(plugin.shown, 1);
      expect(await restarted.deliver(plan()), 0);
      expect(await restarted.deliver(plan(day: '2026-10-20')), 1);
      expect(plugin.shown, 2);
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
  test('bill and cash-review cancellation stay isolated', () async {
    await p.setAccount(testAccount);
    final bills = LocalBillReminderScheduler(
      const FlutterSecureStorage(),
      plugin: plugin,
    );
    await bills.setOwner('alex');
    await bills.clear();
    await bills.replace([]);
    await bills.setOwner(null);
    expect(plugin.visible, {LocalCashReviewDelivery.notificationId});
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
        key: LocalCashReviewDelivery.historyKey,
        value: 'corrupt',
      );
      source.value = plan(day: '2026-10-20');
      await p.refresh();
      expect(p.state.error, isNotNull);
      expect(plugin.shown, 0);
    },
  );
  test(
    'app checks changes and preferences, and deletes cash-review history with account',
    () async {
      final app = testPresenters(
        FakeRepositories()..account = testAccount,
        notificationRepository: prefs,
        cashReviewSource: source,
        cashReviewDelivery: delivery,
      );
      addTearDown(app.dispose);
      await app.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(plugin.shown, 1);
      source.value = plan(day: '2026-10-20');
      await app.budgets.save(
        BudgetDraft(period: '2026-10', limitAmount: 100, alertThreshold: 80),
      );
      await Future<void>.delayed(Duration.zero);
      expect(plugin.shown, 2);
      await app.notifications!.load();
      await app.notifications!.save(prefs.preferences.copy(cashReview: false));
      expect(plugin.visible, isEmpty);
      expect(await app.auth.deleteAccount(), isTrue);
      expect(plugin.visible, isEmpty);
      expect(
        await const FlutterSecureStorage().read(
          key: LocalCashReviewDelivery.historyKey,
        ),
        '{}',
      );
    },
  );

  testWidgets('cash-review status and retry fit a phone at 200 percent text', (
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
        home: NotificationSettingsScreen(presenter: settings, cashReview: p),
      ),
    );
    await tester.pumpAndSettle();
    final check = find.text('Check cash review');
    await tester.scrollUntilVisible(check, 300);
    await tester.pumpAndSettle();
    expect(find.textContaining('Cash-review reminder sent.'), findsOneWidget);
    source.fail = true;
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(
      find.text('Could not check cash-review reminders. Connect and retry.'),
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
