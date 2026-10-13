import 'dart:async';
import 'package:test/test.dart';
import 'package:pocketwise/features/notifications/model/notification_repository.dart';
import 'package:pocketwise/features/notifications/presenter/notification_presenter.dart';
import 'support/fake_notifications.dart';

void main() {
  test(
    'loading and saving choices never prompts; choices survive permission denial and restart',
    () async {
      final repo = FakeNotifications();
      final p = NotificationPresenter(repo);
      addTearDown(p.dispose);
      await p.load();
      expect(p.state.preferences.enabled, isFalse);
      await p.save(
        p.state.preferences.copy(enabled: true, bills: true, billLeadDays: 3),
      );
      expect(repo.requests, 0);
      repo.status = NotificationPermission.denied;
      await p.requestPermission();
      expect(repo.requests, 1);
      expect(p.state.preferences.bills, isTrue);
      final reopened = NotificationPresenter(repo);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.state.preferences.billLeadDays, 3);
      await reopened.save(reopened.state.preferences.copy(enabled: false));
      expect(reopened.state.preferences.bills, isTrue);
      expect(repo.requests, 1);
    },
  );

  test('failed persistence rolls back and blocks duplicate saves', () async {
    final repo = FakeNotifications();
    final p = NotificationPresenter(repo);
    addTearDown(p.dispose);
    await p.load();
    repo.saveGate = Completer<void>();
    repo.failSave = true;
    final pending = p.save(p.state.preferences.copy(enabled: true));
    await p.save(p.state.preferences.copy(bills: true));
    expect(repo.saves, 1);
    repo.saveGate!.complete();
    await pending;
    expect(p.state.preferences.enabled, isFalse);
    expect(p.state.error, isNotNull);
    repo.failSave = false;
    await p.save(p.state.preferences.copy(enabled: true));
    expect(p.state.error, isNull);
  });

  test(
    'permission reentry, revocation, settings failures and disposal are handled',
    () async {
      final repo = FakeNotifications();
      final p = NotificationPresenter(repo);
      await p.load();
      repo.requestGate = Completer<NotificationPermission>();
      final pending = p.requestPermission();
      await p.requestPermission();
      await p.refreshPermission();
      expect(repo.requests, 1);
      repo.requestGate!.complete(NotificationPermission.granted);
      await pending;
      expect(p.state.permission, NotificationPermission.granted);
      repo.status = NotificationPermission.blocked;
      await p.refreshPermission();
      expect(p.state.permission, NotificationPermission.blocked);
      await p.requestPermission();
      expect(repo.requests, 1);
      repo.settingsOpened = false;
      await p.openSettings();
      expect(p.state.permissionError, isNotNull);
      repo.failPermission = true;
      await p.refreshPermission();
      expect(p.state.permission, NotificationPermission.unknown);
      p.dispose();
      final checks = repo.checks;
      await p.refreshPermission();
      expect(repo.checks, checks);
    },
  );

  test(
    'failed load cannot overwrite saved preferences with defaults',
    () async {
      final repo = FakeNotifications()..failLoad = true;
      final p = NotificationPresenter(repo);
      addTearDown(p.dispose);
      await p.load();
      await p.save(const NotificationPreferences(enabled: true));
      expect(repo.saves, 0);
      repo.failLoad = false;
      await p.load();
      expect(p.state.loaded, isTrue);
      expect(p.state.error, isNull);
    },
  );
}
