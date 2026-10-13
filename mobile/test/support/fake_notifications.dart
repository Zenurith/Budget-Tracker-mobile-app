import 'dart:async';
import 'package:pocketwise/features/notifications/model/notification_repository.dart';

class FakeNotifications implements NotificationRepository {
  NotificationPreferences preferences = const NotificationPreferences();
  NotificationPermission status = NotificationPermission.notDetermined;
  bool failLoad = false,
      failSave = false,
      failPermission = false,
      settingsOpened = true;
  int requests = 0, saves = 0, checks = 0, settings = 0;
  Completer<void>? saveGate;
  Completer<NotificationPermission>? requestGate;
  @override
  Future<NotificationPreferences> load() async {
    if (failLoad) throw StateError('Unavailable');
    return preferences;
  }

  @override
  Future<void> save(NotificationPreferences next) async {
    saves++;
    if (saveGate != null) await saveGate!.future;
    if (failSave) throw StateError('Unavailable');
    preferences = next;
  }

  @override
  Future<NotificationPermission> permission() async {
    checks++;
    if (failPermission) throw StateError('Unavailable');
    return status;
  }

  @override
  Future<NotificationPermission> requestPermission() async {
    requests++;
    return requestGate == null ? status : await requestGate!.future;
  }

  @override
  Future<bool> openSettings() async {
    settings++;
    return settingsOpened;
  }
}
