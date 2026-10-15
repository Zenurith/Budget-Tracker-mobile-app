import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../features/notifications/model/budget_alert_repository.dart';

class LocalBudgetAlertDelivery implements BudgetAlertDelivery {
  // Separate from bill date ordinals (1..3652059).
  static const notificationId = 2000000000;
  static const ownerKey = 'budget_alert_owner_v1';
  static const historyKey = 'budget_alert_history_v1';
  final FlutterSecureStorage storage;
  final FlutterLocalNotificationsPlugin plugin;
  bool _initialized = false;
  final Future<void> Function()? initializeNotifications;
  LocalBudgetAlertDelivery(
    this.storage, {
    FlutterLocalNotificationsPlugin? plugin,
    this.initializeNotifications,
  }) : plugin = plugin ?? FlutterLocalNotificationsPlugin();
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
    if (await plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('ic_notification'),
            iOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestSoundPermission: false,
              requestBadgePermission: false,
            ),
          ),
        ) !=
        true) {
      throw StateError('Device alerts could not initialize');
    }
    _initialized = true;
  }

  @override
  Future<void> setOwner(String? owner) async {
    if (!supported) return;
    await _initialize();
    if (owner == null || await storage.read(key: ownerKey) != owner) {
      await clear();
      if (owner == null) {
        await storage.delete(key: ownerKey);
      } else {
        await storage.write(key: ownerKey, value: owner);
      }
    }
  }

  @override
  Future<void> clear() async {
    if (!supported) return;
    await _initialize();
    await plugin.cancel(id: notificationId);
  }

  @override
  Future<void> forgetOwner(String owner) async {
    if (!supported) return;
    final raw = await storage.read(key: historyKey);
    if (raw == null) return;
    final history = jsonDecode(raw) as Map<String, dynamic>;
    history.removeWhere((key, _) => key.startsWith('$owner:'));
    await storage.write(key: historyKey, value: jsonEncode(history));
  }

  @override
  Future<int> deliver(BudgetAlertPlan plan) async {
    if (!supported) return 0;
    await _initialize();
    if (!plan.ready ||
        plan.period == null ||
        await storage.read(key: ownerKey) != plan.ownerId) {
      throw StateError('Invalid alert owner or period');
    }
    final raw = await storage.read(key: historyKey);
    final history = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    final period = DateTime.parse('${plan.period}-01');
    final cutoff =
        '${period.year - 1}-${period.month.toString().padLeft(2, '0')}';
    history.removeWhere((key, _) => key.split(':').last.compareTo(cutoff) < 0);
    final key = '${plan.ownerId}:${plan.period}';
    final seen = (history[key] as List? ?? []).cast<String>().toSet();
    final fresh = plan.budgetIds.toSet().difference(seen);
    if (plan.budgetIds.isEmpty) await clear();
    if (fresh.isEmpty) return 0;
    // Persist before posting: a crash/ambiguous native error must not cause a
    // repeated alert. This records an attempt, not proof of OS delivery.
    history[key] = {...seen, ...fresh}.toList();
    await storage.write(key: historyKey, value: jsonEncode(history));
    await plugin.show(
      id: notificationId,
      payload: jsonEncode({
        'type': 'budget_review_v1',
        'owner': plan.ownerId,
        'period': plan.period,
        'ids': fresh.toList(),
      }),
      title: 'Budget threshold reached',
      body:
          '${fresh.length} budget${fresh.length == 1 ? ' has' : 's have'} reached the alert threshold for ${plan.period}. Open Pocketwise to review your spending.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'budget_alerts_v1',
          'Budget alerts',
          channelDescription: 'Monthly budget spending thresholds',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          visibility: NotificationVisibility.private,
        ),
        iOS: DarwinNotificationDetails(presentBadge: false),
      ),
    );
    return fresh.length;
  }
}
