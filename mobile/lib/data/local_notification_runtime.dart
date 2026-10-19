import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// All notification features share one native callback and cold-start check.
class LocalNotificationRuntime {
  final FlutterLocalNotificationsPlugin plugin;
  final void Function(String?) onTap;
  Future<void>? _initialization;
  LocalNotificationRuntime(this.plugin, this.onTap);
  Future<void> initialize() =>
      _initialization ??= _start().catchError((Object error) {
        _initialization = null;
        throw error;
      });
  Future<void> _start() async {
    if (kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
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
      onDidReceiveNotificationResponse: (response) => onTap(response.payload),
    );
    if (result != true) {
      throw StateError('Device notifications could not initialize');
    }
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      onTap(launch!.notificationResponse?.payload);
    }
  }
}
