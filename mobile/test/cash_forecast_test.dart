import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/features/forecast/model/forecast_repository.dart';
import 'package:pocketwise/features/forecast/presenter/forecast_presenter.dart';
import 'package:pocketwise/models/finance.dart';
import 'support/fake_repositories.dart';

class FakeForecast implements ForecastRepository {
  Completer<Json> pending = Completer<Json>();
  int calls = 0;
  @override
  Future<Json> calculate(Json assumptions) {
    calls++;
    return pending.future;
  }
}

void main() {
  test('discards responses after assumptions or owner change', () async {
    for (final logout in [false, true]) {
      final repo = FakeForecast();
      final presenter = ForecastPresenter(repo, syncBlocked: () => false);
      presenter.setAccount(testAccount);
      final request = presenter.calculate({});
      if (logout) {
        presenter.setAccount(null);
      } else {
        presenter.invalidate();
      }
      repo.pending.complete({'ready': true});
      await request;
      expect(presenter.state.result, isEmpty);
      presenter.dispose();
    }
  });
  test('blocks pending sync and expires projected balances', () async {
    final repo = FakeForecast();
    var blocked = true;
    var now = DateTime.utc(2026, 10, 20);
    final presenter = ForecastPresenter(
      repo,
      syncBlocked: () => blocked,
      now: () => now,
    );
    presenter.setAccount(testAccount);
    await presenter.calculate({});
    expect(repo.calls, 0);
    expect(presenter.state.error, contains('Sync pending'));
    blocked = false;
    final request = presenter.calculate({});
    repo.pending.complete({
      'ready': true,
      'expires_at': now.add(const Duration(minutes: 5)).toIso8601String(),
    });
    await request;
    expect(presenter.state.result['ready'], true);
    now = now.add(const Duration(minutes: 5));
    presenter.expire();
    expect(presenter.state.result, isEmpty);
    presenter.dispose();
  });
}
