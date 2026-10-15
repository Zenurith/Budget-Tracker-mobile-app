import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:pocketwise/data/local_bill_reminder_scheduler.dart';
import 'package:pocketwise/features/notifications/model/bill_reminder_repository.dart';

class DeviceNotifications implements FlutterLocalNotificationsPlugin {
  final Map<int, tz.TZDateTime> pending = {};
  InitializationSettings? settings;
  int cancellations = 0;
  bool fail = false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    this.settings = settings;
    return true;
  }

  @override
  Future<void> cancelAll() async {
    cancellations++;
    pending.clear();
  }

  @override
  Future<void> cancel({required int id, String? tag}) async {
    pending.remove(id);
  }

  @override
  Future<List<PendingNotificationRequest>>
  pendingNotificationRequests() async => pending.keys
      .map((id) => PendingNotificationRequest(id, null, null, null))
      .toList();
  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    expect(androidScheduleMode, AndroidScheduleMode.inexactAllowWhileIdle);
    expect(
      notificationDetails.android!.visibility,
      NotificationVisibility.private,
    );
    expect(body, isNot(contains('Rent')));
    if (fail) throw StateError('Scheduling failed');
    pending[id] = scheduledDate;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DeviceNotifications plugin;
  late LocalBillReminderScheduler scheduler;
  var clock = DateTime.utc(2026, 10, 14);
  BillReminder reminder(int id, [int hour = 9]) => BillReminder(
    id: id,
    count: 1,
    dueDate: '2026-10-20',
    fireAt: DateTime.utc(2026, 10, 19, hour),
  );
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterSecureStorage.setMockInitialValues({});
    clock = DateTime.utc(2026, 10, 14);
    plugin = DeviceNotifications();
    scheduler = LocalBillReminderScheduler(
      const FlutterSecureStorage(),
      plugin: plugin,
      now: () => clock,
    );
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'initialization never prompts; stable IDs replace edits and cancel removed bills',
    () async {
      await scheduler.setOwner('alex');
      expect(plugin.settings!.iOS!.requestAlertPermission, isFalse);
      expect(plugin.settings!.iOS!.requestBadgePermission, isFalse);
      expect(await scheduler.replace([reminder(1), reminder(2)]), 2);
      await scheduler.replace([reminder(1, 10)]);
      expect(plugin.pending.keys, [1]);
      expect(plugin.pending[1]!.hour, 10);
      await scheduler.replace([reminder(1, 10)]);
      expect(plugin.pending.length, 1);
      await scheduler.replace([]);
      expect(plugin.pending, isEmpty);
    },
  );
  test(
    'restart preserves owner and elapsed reminder history prevents replay after lead change',
    () async {
      await scheduler.setOwner('alex');
      await scheduler.replace([reminder(1)]);
      clock = DateTime.utc(2026, 10, 19, 10);
      plugin.pending.clear(); // OS has delivered the reminder.
      final restarted = LocalBillReminderScheduler(
        const FlutterSecureStorage(),
        plugin: plugin,
        now: () => clock,
      );
      await restarted.setOwner('alex');
      expect(await restarted.replace([reminder(1, 11)]), 0);
      expect(plugin.pending, isEmpty);
      await restarted.setOwner('new-account');
      expect(await restarted.replace([reminder(1, 11)]), 1);
      await restarted.setOwner(null);
      expect(plugin.pending, isEmpty);
      expect(
        await const FlutterSecureStorage().read(
          key: LocalBillReminderScheduler.ownerKey,
        ),
        isNull,
      );
    },
  );
  test(
    'partial native failure clears alerts; invalid batches never silently overwrite',
    () async {
      await scheduler.setOwner('alex');
      await scheduler.replace([reminder(1)]);
      plugin.fail = true;
      await expectLater(scheduler.replace([reminder(2)]), throwsStateError);
      expect(plugin.pending, isEmpty);
      await expectLater(
        scheduler.replace([reminder(1), reminder(1)]),
        throwsStateError,
      );
    },
  );
  test('unsupported targets never initialize the native plugin', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await scheduler.setOwner('alex');
    await scheduler.clear();
    expect(await scheduler.replace([reminder(1)]), 0);
    expect(plugin.settings, isNull);
  });
}
