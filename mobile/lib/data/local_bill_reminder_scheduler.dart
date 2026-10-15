import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/timezone.dart' as tz;
import '../features/notifications/model/bill_reminder_repository.dart';

class LocalBillReminderScheduler implements BillReminderScheduler {
  static const ownerKey = 'bill_reminder_owner_v1';
  static const historyKey = 'bill_reminder_history_v1';
  final FlutterSecureStorage storage;
  final FlutterLocalNotificationsPlugin plugin;
  final DateTime Function() now;
  bool _initialized = false;
  final Future<void> Function()? initializeNotifications;
  LocalBillReminderScheduler(
    this.storage, {
    FlutterLocalNotificationsPlugin? plugin,
    this.initializeNotifications,
    DateTime Function()? now,
  }) : plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       now = now ?? DateTime.now;
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _initialize() async {
    if (_initialized) return;
    if (initializeNotifications != null) {
      await initializeNotifications!();
      _initialized = true;
      return;
    }
    final result = await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
    if (result != true) {
      throw StateError('Device reminders could not initialize');
    }
    _initialized = true;
  }

  Future<void> _cancelBills() async {
    // Bill IDs are date ordinals. Never cancel another notification feature.
    final ids = <int>{
      for (final request in await plugin.pendingNotificationRequests())
        if (request.id > 0 && request.id <= 3652059) request.id,
    };
    for (final id in ids) {
      await plugin.cancel(id: id);
    }
    for (final key in (await _history()).keys) {
      final id = int.tryParse(key);
      if (id != null && id > 0 && id <= 3652059 && !ids.contains(id)) {
        await plugin.cancel(id: id);
      }
    }
  }

  Future<Map<String, int>> _history() async {
    final raw = await storage.read(key: historyKey);
    if (raw == null) return {};
    return (jsonDecode(raw) as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, value as int),
    );
  }

  Map<String, int> _past(Map<String, int> entries) {
    final time = now().millisecondsSinceEpoch;
    final cutoff = now()
        .subtract(const Duration(days: 90))
        .millisecondsSinceEpoch;
    return {
      for (final entry in entries.entries)
        if (entry.value <= time && entry.value >= cutoff)
          entry.key: entry.value,
    };
  }

  @override
  Future<void> setOwner(String? ownerId) async {
    if (!supported) return;
    await _initialize();
    final previous = await storage.read(key: ownerKey);
    if (ownerId == null || previous != ownerId) {
      await _cancelBills();
      await storage.delete(key: historyKey);
      if (ownerId == null) {
        await storage.delete(key: ownerKey);
      } else {
        await storage.write(key: ownerKey, value: ownerId);
      }
    }
  }

  @override
  Future<void> clear() async {
    if (!supported) return;
    await _initialize();
    // Cancel first: even a storage failure must not leave known stale alerts.
    await _cancelBills();
    await storage.write(
      key: historyKey,
      value: jsonEncode(_past(await _history())),
    );
  }

  @override
  Future<int> replace(List<BillReminder> reminders) async {
    if (!supported) return 0;
    await _initialize();
    if (await storage.read(key: ownerKey) == null) {
      throw StateError('Sign in before scheduling');
    }
    final past = _past(await _history());
    final desired =
        reminders
            .where(
              (r) => r.fireAt.isAfter(now()) && !past.containsKey('${r.id}'),
            )
            .toList()
          ..sort((a, b) => a.fireAt.compareTo(b.fireAt));
    if (desired.length > 60 ||
        desired.map((r) => r.id).toSet().length != desired.length) {
      throw StateError('Invalid reminder batch');
    }
    try {
      var scheduled = 0;
      final ids = desired.map((r) => r.id).toSet();
      for (final pending in await plugin.pendingNotificationRequests()) {
        if (pending.id > 0 &&
            pending.id <= 3652059 &&
            !ids.contains(pending.id)) {
          await plugin.cancel(id: pending.id);
        }
      }
      for (final reminder in desired) {
        if (!reminder.fireAt.isAfter(now())) continue;
        await plugin.zonedSchedule(
          id: reminder.id,
          title: 'Upcoming bill reminder',
          body:
              '${reminder.count} unpaid bill${reminder.count == 1 ? '' : 's'} or debt payment${reminder.count == 1 ? '' : 's'} due ${reminder.dueDate}. Open Pocketwise to review your financial plan.',
          scheduledDate: tz.TZDateTime.from(reminder.fireAt, tz.UTC),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'bill_reminders_v1',
              'Bill reminders',
              channelDescription: 'Upcoming unpaid bills and debt payments',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
              visibility: NotificationVisibility.private,
            ),
            iOS: DarwinNotificationDetails(presentBadge: false),
          ),
        );
        past['${reminder.id}'] = reminder.fireAt.millisecondsSinceEpoch;
        scheduled++;
      }
      await storage.write(key: historyKey, value: jsonEncode(past));
      return scheduled;
    } catch (_) {
      await _cancelBills();
      rethrow;
    }
  }
}
