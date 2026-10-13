import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/data/device_notification_repository.dart';
import 'package:pocketwise/features/notifications/model/notification_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DeviceNotificationRepository.channel, null);
  });
  test(
    'device choices round-trip across repository instances without permission prompts',
    () async {
      final first = DeviceNotificationRepository(const FlutterSecureStorage());
      expect((await first.load()).enabled, isFalse);
      await first.save(
        const NotificationPreferences(
          enabled: true,
          bills: true,
          budgets: true,
          billLeadDays: 7,
        ),
      );
      final second = DeviceNotificationRepository(const FlutterSecureStorage());
      final preferences = await second.load();
      expect(preferences.enabled, isTrue);
      expect(preferences.billLeadDays, 7);
      expect(preferences.cashReview, isFalse);
      FlutterSecureStorage.setMockInitialValues({
        DeviceNotificationRepository.storageKey: '{"version":99}',
      });
      await expectLater(second.load(), throwsFormatException);
    },
  );
  test(
    'native permission bridge maps statuses and unsupported platforms make no calls',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DeviceNotificationRepository.channel, (
            MethodCall call,
          ) async {
            calls.add(call.method);
            return switch (call.method) {
              'status' => 'denied',
              'request' => 'granted',
              _ => true,
            };
          });
      final repo = DeviceNotificationRepository(const FlutterSecureStorage());
      expect(await repo.permission(), NotificationPermission.denied);
      expect(await repo.requestPermission(), NotificationPermission.granted);
      expect(await repo.openSettings(), isTrue);
      expect(calls, ['status', 'request', 'openSettings']);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(await repo.permission(), NotificationPermission.unsupported);
      expect(
        await repo.requestPermission(),
        NotificationPermission.unsupported,
      );
      expect(await repo.openSettings(), isFalse);
      expect(calls.length, 3);
    },
  );
}
