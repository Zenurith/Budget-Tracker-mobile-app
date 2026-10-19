import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../features/notifications/model/cash_review_repository.dart';

class LocalCashReviewDelivery implements CashReviewDelivery {
  // Separate from bill date ordinals (1..3652059).
  static const notificationId = 2000000001;
  static const ownerKey = 'cash_review_owner_v1';
  static const historyKey = 'cash_review_history_v1';
  final FlutterSecureStorage storage;
  final FlutterLocalNotificationsPlugin plugin;
  bool _initialized = false;
  final Future<void> Function()? initializeNotifications;
  LocalCashReviewDelivery(
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
    history.remove(owner);
    await storage.write(key: historyKey, value: jsonEncode(history));
  }

  @override
  Future<int> deliver(CashReviewPlan plan) async {
    if (!supported) return 0;
    await _initialize();
    if (!plan.needsReview ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(plan.day) ||
        await storage.read(key: ownerKey) != plan.ownerId) {
      throw StateError('Invalid cash-review owner or date');
    }
    final raw = await storage.read(key: historyKey);
    final history = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    // One attempt per local day, including across restarts and preference changes.
    // A single last-attempt date per owner also bounds history growth.
    final previous = history[plan.ownerId] as String?;
    if (previous != null && previous.compareTo(plan.day) >= 0) return 0;
    history[plan.ownerId] = plan.day;
    await storage.write(key: historyKey, value: jsonEncode(history));
    await plugin.show(
      id: notificationId,
      payload: jsonEncode({'type': 'cash_review_v1', 'owner': plan.ownerId}),
      title: 'Time to review your cash',
      body:
          'Your cash balances or funding plan need review. Open Protected Funding to check what changed.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'cash_review_v1',
          'Cash review reminders',
          channelDescription:
              'Reminders to reconcile cash and review protected funding',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          visibility: NotificationVisibility.private,
        ),
        iOS: DarwinNotificationDetails(presentBadge: false),
      ),
    );
    return 1;
  }
}
