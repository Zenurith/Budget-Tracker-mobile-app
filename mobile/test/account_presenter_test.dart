import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:pocketwise/core/model/contracts.dart';
import 'package:pocketwise/features/auth/presenter/auth_presenter.dart';
import 'support/fake_repositories.dart';

class MemoryDestination implements ExportDestination {
  String? contents;
  bool cancel = false;
  @override
  Future<bool> save(String contents) async {
    this.contents = contents;
    return !cancel;
  }
}

void main() {
  test('profile rejects invalid names and concurrent submissions', () async {
    final repo = FakeRepositories()..account = testAccount;
    final presenter = AuthPresenter(repo);
    addTearDown(presenter.dispose);
    await presenter.initialize();
    expect(await presenter.updateProfile('  '), isFalse);
    expect(await presenter.updateProfile('a' * 81), isFalse);
    expect(repo.profileUpdates, 0);
    repo.profileGate = Completer<Account>();
    final saving = presenter.updateProfile('Alex Tan');
    expect(presenter.state.busy, isTrue);
    expect(await presenter.updateProfile('Again'), isFalse);
    expect(await presenter.logout(), isFalse);
    repo.profileGate!.complete(
      const Account(
        id: 'alex',
        name: 'Alex Tan',
        email: 'alex@example.com',
        currency: 'MYR',
      ),
    );
    expect(await saving, isTrue);
    expect(presenter.state.account!.name, 'Alex Tan');
    expect(repo.profileUpdates, 1);
  });

  test('profile failure keeps account and permits retry', () async {
    final repo = FakeRepositories()..account = testAccount;
    final presenter = AuthPresenter(repo);
    addTearDown(presenter.dispose);
    await presenter.initialize();
    repo.failure = 'offline';
    expect(await presenter.updateProfile('New name'), isFalse);
    expect(presenter.state.account, testAccount);
    expect(presenter.state.error, contains('offline'));
    repo.failure = null;
    expect(await presenter.updateProfile('  New name  '), isTrue);
    expect(presenter.state.account!.name, 'New name');
  });

  test(
    'profile update preserves selected month and in-flight overview data',
    () async {
      final repo = FakeRepositories()..account = testAccount;
      final app = testPresenters(repo);
      addTearDown(app.dispose);
      await app.initialize();
      await app.overview.showMonth(DateTime(2025, 6));
      final pending = Completer<MonthlySnapshot>();
      repo.onLoad = (_) => pending.future;
      final loading = app.overview.reload();
      await app.auth.updateProfile('Renamed');
      await Future<void>.delayed(Duration.zero);
      expect(app.overview.user!.name, 'Renamed');
      pending.complete(MonthlySnapshot(summary: {'income': 123}));
      await loading;
      expect(app.overview.user!.name, 'Renamed');
      expect(app.overview.month, DateTime(2025, 6));
      expect(app.overview.summary['income'], 123);
    },
  );

  test('export handles duplicate clicks, cancellation and retry', () async {
    final repo = FakeRepositories()..account = testAccount;
    final presenter = AuthPresenter(repo);
    final destination = MemoryDestination();
    addTearDown(presenter.dispose);
    await presenter.initialize();
    repo.exportGate = Completer<Map<String, dynamic>>();
    final export = presenter.exportData(destination);
    expect(await presenter.exportData(destination), isFalse);
    repo.exportGate!.complete({
      'schema_version': 1,
      'account': {'name': 'Alex'},
    });
    expect(await export, isTrue);
    expect(jsonDecode(destination.contents!)['schema_version'], 1);
    expect(repo.exports, 1);
    repo.exportGate = null;
    destination.cancel = true;
    expect(await presenter.exportData(destination), isFalse);
    expect(presenter.state.error, isNull);
    repo.failure = 'offline';
    expect(await presenter.exportData(destination), isFalse);
    expect(presenter.state.error, contains('offline'));
    repo.failure = null;
    destination.cancel = false;
    expect(await presenter.exportData(destination), isTrue);
  });

  test(
    'disposed export never opens destination with late private data',
    () async {
      final repo = FakeRepositories()..account = testAccount;
      final presenter = AuthPresenter(repo);
      final destination = MemoryDestination();
      await presenter.initialize();
      repo.exportGate = Completer<Map<String, dynamic>>();
      final pending = presenter.exportData(destination);
      presenter.dispose();
      repo.exportGate!.complete({
        'account': {'name': 'Private'},
      });
      expect(await pending, isFalse);
      expect(destination.contents, isNull);
    },
  );
}
