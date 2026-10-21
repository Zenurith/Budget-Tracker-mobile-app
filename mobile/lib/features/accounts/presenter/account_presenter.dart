import 'dart:convert';
import 'dart:math';
import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';
import '../../../models/finance.dart';
import '../model/account_repository.dart';

class AccountState {
  final Json data;
  final bool busy;
  final String? error;
  AccountState({Json data = const {}, this.busy = false, this.error})
    : data = freezeJson(data);
}

class AccountPresenter extends Presenter<AccountState> {
  final AccountRepository repository;
  final bool Function() syncBlocked;
  String? _owner, _fingerprint, _operation;
  int _generation = 0;
  AccountPresenter(this.repository, {required this.syncBlocked})
    : super(AccountState());
  void setAccount(Account? account) {
    _generation++;
    _owner = account?.id;
    _fingerprint = _operation = null;
    emit(AccountState());
  }

  Future<void> reload() async {
    if (_owner == null || disposed || state.busy) return;
    final generation = _generation;
    emit(AccountState(busy: true));
    try {
      if (syncBlocked()) {
        throw StateError(
          'Sync pending transactions before reviewing account balances.',
        );
      }
      final data = await repository.load();
      if (generation == _generation && !disposed) {
        emit(AccountState(data: data));
      }
    } catch (e) {
      if (generation == _generation) emit(AccountState(error: e.toString()));
    }
  }

  void invalidate() {
    _generation++;
    emit(AccountState());
  }

  Future<bool> save(String action, Json draft) async {
    if (_owner == null || disposed || state.busy) return false;
    final generation = _generation;
    final old = state.data;
    emit(AccountState(data: old, busy: true));
    try {
      if (syncBlocked()) {
        throw StateError('Sync pending transactions before changing accounts.');
      }
      final fingerprint = jsonEncode([action, draft]);
      if (_fingerprint != fingerprint) {
        _fingerprint = fingerprint;
        _operation = base64UrlEncode(
          List.generate(24, (_) => Random.secure().nextInt(256)),
        );
      }
      await repository.save(action, {...draft, 'operation_id': _operation});
      if (generation != _generation || disposed) return false;
      _fingerprint = _operation = null;
      emit(AccountState());
      effect(const DataChanged());
      await reload();
      return generation == _generation && !disposed;
    } catch (e) {
      if (generation == _generation) {
        emit(AccountState(data: old, error: e.toString()));
      }
      return false;
    }
  }
}
