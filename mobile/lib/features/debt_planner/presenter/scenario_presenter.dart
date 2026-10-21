import 'dart:convert';
import 'dart:math';
import '../../../core/presentation/presenter.dart';
import '../../../core/model/contracts.dart';
import '../../../models/finance.dart';
import '../model/scenario_repository.dart';

class ScenarioState {
  final Json data;
  final bool busy;
  final String? error;
  ScenarioState({Json data = const {}, this.busy = false, this.error})
    : data = freezeJson(data);
}

class ScenarioPresenter extends Presenter<ScenarioState> {
  final ScenarioRepository repository;
  String? owner, _fingerprint, _operation;
  int _generation = 0;
  ScenarioPresenter(this.repository) : super(ScenarioState());
  void setAccount(Account? account) {
    owner = account?.id;
    _generation++;
    _fingerprint = _operation = null;
    emit(ScenarioState());
  }

  Future<bool> run(Future<void> Function() action) async {
    if (owner == null || state.busy || disposed) return false;
    final generation = _generation;
    emit(ScenarioState(data: state.data, busy: true));
    try {
      await action();
      if (generation != _generation || disposed) return false;
      final data = await repository.load();
      if (generation != _generation || disposed) return false;
      emit(ScenarioState(data: data));
      return true;
    } catch (e) {
      if (generation == _generation && !disposed) {
        emit(ScenarioState(data: state.data, error: e.toString()));
      }
      return false;
    }
  }

  Future<bool> reload() => run(() async {});
  Future<bool> save(Json draft) {
    if (state.busy || owner == null || disposed) return Future.value(false);
    final fingerprint = jsonEncode(draft);
    if (_fingerprint != fingerprint) {
      _fingerprint = fingerprint;
      final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
      bytes[6] = (bytes[6] & 15) | 64;
      bytes[8] = (bytes[8] & 63) | 128;
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      _operation =
          '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    }
    return run(() async {
      await repository.save({...draft, 'operation_id': _operation});
    });
  }

  Future<bool> delete(String id) => run(() => repository.delete(id));
}
