import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../features/notifications/model/notification_repository.dart';

/// Device preferences are independent of account data and OS authorization.
class DeviceNotificationRepository implements NotificationRepository {
  static const storageKey = 'notification_preferences_v1';
  static const channel = MethodChannel('pocketwise/notifications');
  final FlutterSecureStorage storage;
  DeviceNotificationRepository(this.storage);
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<NotificationPreferences> load() async {
    final raw = await storage.read(key: storageKey);
    return raw == null
        ? const NotificationPreferences()
        : NotificationPreferences.fromJson(
            jsonDecode(raw) as Map<String, dynamic>,
          );
  }

  @override
  Future<void> save(NotificationPreferences preferences) =>
      storage.write(key: storageKey, value: jsonEncode(preferences.toJson()));

  Future<NotificationPermission> _status(String method) async {
    if (!supported) return NotificationPermission.unsupported;
    final value = await channel.invokeMethod<String>(method);
    return NotificationPermission.values.firstWhere(
      (s) => s.name == value,
      orElse: () => NotificationPermission.unknown,
    );
  }

  @override
  Future<NotificationPermission> permission() => _status('status');
  @override
  Future<NotificationPermission> requestPermission() => _status('request');
  @override
  Future<bool> openSettings() async =>
      supported && (await channel.invokeMethod<bool>('openSettings') ?? false);
}
