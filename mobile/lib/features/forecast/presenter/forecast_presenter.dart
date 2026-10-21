import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';
import '../../../models/finance.dart';
import '../model/forecast_repository.dart';

class ForecastState {
  final Json result;
  final bool busy;
  final String? error;
  ForecastState({Json result = const {}, this.busy = false, this.error})
    : result = freezeJson(result);
}

class ForecastPresenter extends Presenter<ForecastState> {
  final ForecastRepository repository;
  final bool Function() syncBlocked;
  final DateTime Function() now;
  String? _owner;
  int _request = 0;
  ForecastPresenter(
    this.repository, {
    required this.syncBlocked,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now,
       super(ForecastState());
  void setAccount(Account? account) {
    _owner = account?.id;
    invalidate();
  }

  void invalidate() {
    ++_request;
    emit(ForecastState());
  }

  void expire() {
    final expiry = DateTime.tryParse('${state.result['expires_at']}');
    if (expiry != null && !now().isBefore(expiry)) invalidate();
  }

  Future<void> calculate(Json assumptions) async {
    if (_owner == null || disposed || state.busy) return;
    final request = ++_request;
    emit(ForecastState(busy: true));
    try {
      if (syncBlocked()) {
        throw StateError('Sync pending transactions before forecasting cash.');
      }
      final result = await repository.calculate(assumptions);
      if (request != _request || disposed) return;
      if (syncBlocked()) {
        throw StateError('Sync pending transactions before forecasting cash.');
      }
      emit(ForecastState(result: result));
      expire();
    } catch (e) {
      if (request == _request && !disposed) {
        emit(ForecastState(error: e.toString()));
      }
    }
  }
}
