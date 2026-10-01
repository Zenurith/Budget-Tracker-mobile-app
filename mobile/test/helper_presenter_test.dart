import 'dart:async';
import 'package:test/test.dart';
import 'package:pocketwise/features/financial_helper/presenter/helper_presenter.dart';
import 'package:pocketwise/models/finance.dart';
import 'support/fake_repositories.dart';

void main() {
  test(
    'invalid scenario inputs are rejected before repository access',
    () async {
      final repo = FakeHelperRepository();
      final p = HelperPresenter(repo)..setAccount(testAccount);
      addTearDown(p.dispose);
      await p.reload();
      expect(
        await p.preview({'additional_debt_monthly': -1}, '2026-10-01'),
        false,
      );
      expect(await p.preview({}, '2026-02-30'), false);
      expect(repo.lastScenario, isNull);
      expect(p.state.error, isNotNull);
    },
  );

  test('load, incomplete results and nested state are immutable', () async {
    final repo = FakeHelperRepository();
    repo.baseline['complete'] = false;
    repo.baseline['ratios']['dsr']['value'] = null;
    final p = HelperPresenter(repo)..setAccount(testAccount);
    addTearDown(p.dispose);
    await p.reload();
    expect(p.state.baseline['complete'], false);
    expect(p.state.baseline['ratios']['dsr']['value'], isNull);
    expect(
      () => p.state.baseline['ratios']['dsr']['value'] = '0',
      throwsUnsupportedError,
    );
    expect(await p.save(' '), false);
    expect(repo.saves, 0);
  });

  test('logout and disposal suppress late private responses', () async {
    final repo = FakeHelperRepository()..calculateGate = Completer<Json>();
    final p = HelperPresenter(repo)..setAccount(testAccount);
    addTearDown(p.dispose);
    final pending = p.reload();
    p.setAccount(null);
    repo.calculateGate!.complete(repo.baseline);
    await pending;
    expect(p.state.baseline, isEmpty);
    expect(await p.save('Private'), false);
    repo.calculateGate = null;
    p.setAccount(testAccount);
    await p.reload();
    repo.scenarioGate = Completer<Json>();
    final preview = p.preview({'additional_debt_monthly': 100}, '2026-10-01');
    p.dispose();
    repo.scenarioGate!.complete({
      'baseline': repo.baseline,
      'scenario': repo.baseline,
    });
    expect(await preview, false);
  });

  test('newer reload wins and failed reads remain stale until retry', () async {
    final repo = FakeHelperRepository()..calculateGate = Completer<Json>();
    final old = repo.calculateGate!;
    final p = HelperPresenter(repo)..setAccount(testAccount);
    addTearDown(p.dispose);
    final first = p.reload();
    repo.calculateGate = null;
    repo.baseline['source_revision'] = 5;
    await p.reload();
    old.complete({...repo.baseline, 'source_revision': 1});
    await first;
    expect(p.state.baseline['source_revision'], 5);
    repo.failure = 'offline';
    await p.reload();
    expect(p.state.stale, true);
    expect(p.state.canSave, false);
    repo.failure = null;
    await p.reload();
    expect(p.state.stale, false);
  });

  test(
    'scenarios use account currency and source revision; discard does not save',
    () async {
      final repo = FakeHelperRepository();
      final p = HelperPresenter(repo)..setAccount(testAccount);
      addTearDown(p.dispose);
      await p.reload();
      expect(
        await p.preview({
          'currency': 'USD',
          'additional_debt_monthly': 40000,
        }, '2026-11-01'),
        true,
      );
      expect(repo.lastScenario!['assumptions']['currency'], 'MYR');
      expect(repo.lastScenario!['expected_revision'], 0);
      expect(repo.lastScenario!['effective_date'], '2026-11-01');
      expect(p.state.scenario, isNotEmpty);
      await p.discardScenario();
      expect(p.state.scenario, isEmpty);
      expect(repo.saves, 0);
    },
  );

  test(
    'snapshot retries keep operation IDs through refresh and block double clicks',
    () async {
      final repo = FakeHelperRepository();
      final p = HelperPresenter(repo)..setAccount(testAccount);
      addTearDown(p.dispose);
      await p.reload();
      repo.failure = 'timeout after save';
      expect(await p.save('Baseline'), false);
      final id = repo.lastSave!['operation_id'];
      repo.failure = null;
      await p.reload();
      repo.saveGate = Completer<Json>();
      final saving = p.save('Baseline');
      expect(await p.save('Baseline'), false);
      expect(repo.lastSave!['operation_id'], id);
      repo.saveGate!.complete({
        'id': 'saved',
        'name': 'Baseline',
        'result': repo.baseline,
      });
      expect(await saving, true);
      expect(p.state.snapshots.length, 1);
      expect(p.state.saving, false);
    },
  );

  test('input changes invalidate calculations and pending responses', () async {
    final repo = FakeHelperRepository();
    final p = HelperPresenter(repo)..setAccount(testAccount);
    addTearDown(p.dispose);
    await p.reload();
    repo.scenarioGate = Completer<Json>();
    final work = p.preview({}, '2026-10-01');
    p.invalidate(2);
    repo.scenarioGate!.complete({
      'baseline': repo.baseline,
      'scenario': repo.baseline,
    });
    expect(await work, false);
    expect(p.state.stale, true);
    expect(await p.save('Stale'), false);
    expect(await p.preview({}, '2026-10-01'), false);
  });
}
