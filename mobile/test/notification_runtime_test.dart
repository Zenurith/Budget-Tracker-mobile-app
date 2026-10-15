import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/data/local_notification_runtime.dart';
import 'package:pocketwise/data/local_bill_reminder_scheduler.dart';
import 'package:pocketwise/data/local_budget_alert_delivery.dart';
import 'bill_reminder_scheduler_test.dart' show DeviceNotifications;

class TapPlugin extends DeviceNotifications {
  int initializations = 0, launches = 0;
  bool failLaunch = false;
  DidReceiveNotificationResponseCallback? callback;
  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializations++;
    callback = onDidReceiveNotificationResponse;
    return super.initialize(settings: settings);
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async {
    launches++;
    if (failLaunch) throw StateError('launch lookup failed');
    return const NotificationAppLaunchDetails(
      true,
      notificationResponse: NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: 'cold',
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test(
    'both features share tap handling; cold launch is consumed once and warm taps continue',
    () async {
      final plugin = TapPlugin();
      final taps = <String?>[];
      final runtime = LocalNotificationRuntime(plugin, taps.add);
      final bills = LocalBillReminderScheduler(
        const FlutterSecureStorage(),
        plugin: plugin,
        initializeNotifications: runtime.initialize,
      );
      final budgets = LocalBudgetAlertDelivery(
        const FlutterSecureStorage(),
        plugin: plugin,
        initializeNotifications: runtime.initialize,
      );
      await Future.wait([
        bills.setOwner('alex'),
        budgets.setOwner('alex'),
        runtime.initialize(),
      ]);
      expect(plugin.initializations, 1);
      expect(plugin.launches, 1);
      expect(taps, ['cold']);
      plugin.callback!(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: 'warm',
        ),
      );
      expect(taps, ['cold', 'warm']);
      expect(plugin.settings!.iOS!.requestAlertPermission, isFalse);
    },
  );
  test(
    'failed initialization can retry without losing callback; unsupported targets do nothing',
    () async {
      final plugin = TapPlugin()..failLaunch = true;
      final runtime = LocalNotificationRuntime(plugin, (_) {});
      await expectLater(runtime.initialize(), throwsStateError);
      plugin.failLaunch = false;
      await runtime.initialize();
      expect(plugin.launches, 2);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final unsupported = TapPlugin();
      await LocalNotificationRuntime(unsupported, (_) {}).initialize();
      expect(unsupported.initializations, 0);
    },
  );
}
