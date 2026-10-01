import 'dart:convert';
import 'dart:math';
import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';
import '../../../models/finance.dart';
import '../model/planning_repository.dart';

class PlanningState {
  final Json data;
  final DateTime month;
  final bool busy, saving;
  final String? error;
  PlanningState({
    required this.month,
    Json data = const {},
    this.busy = false,
    this.saving = false,
    this.error,
  }) : data = freezeJson(data);
  int get revision => data['revision'] as int? ?? 0;
  Json? get profile => data['profile'] as Json?;
  List<Json> items(String key) => (data[key] as List? ?? []).cast<Json>();
}

class PlanningPresenter extends Presenter<PlanningState> {
  final PlanningRepository _repository;
  Account? _account;
  int _request = 0, _owner = 0;
  Json? _pendingPayment;
  String? _pendingFingerprint;
  PlanningPresenter(this._repository, {DateTime Function()? now})
    : super(PlanningState(month: (now ?? DateTime.now)()));

  Future<void> setAccount(Account? account, DateTime month) async {
    _owner++;
    _request++;
    _account = account;
    _pendingPayment = null;
    _pendingFingerprint = null;
    emit(PlanningState(month: DateTime(month.year, month.month)));
    if (account != null) await reload();
  }

  Future<void> changeMonth(int offset) async {
    if (state.saving) return;
    emit(
      PlanningState(
        month: DateTime(state.month.year, state.month.month + offset),
      ),
    );
    await reload();
  }

  Future<void> reload() async {
    if (_account == null || disposed || state.saving) return;
    await _load();
  }

  Future<void> _load({bool saving = false}) async {
    final request = ++_request;
    final month = state.month;
    final previous = state.data;
    emit(
      PlanningState(month: month, data: previous, busy: true, saving: saving),
    );
    try {
      final data = await _repository.load(month);
      if (request != _request || disposed) return;
      emit(PlanningState(month: month, data: data));
    } catch (error) {
      if (request != _request || disposed) return;
      emit(
        PlanningState(month: month, data: previous, error: error.toString()),
      );
    }
  }

  Future<bool> _save(
    Future<void> Function(int) operation, {
    bool reportsChanged = false,
  }) async {
    if (_account == null || state.saving || state.busy || disposed) {
      return false;
    }
    final owner = _owner;
    final revision = state.revision;
    _request++;
    emit(PlanningState(month: state.month, data: state.data, saving: true));
    try {
      await operation(revision);
      if (owner != _owner || disposed) return false;
      if (reportsChanged) effect(const DataChanged());
      await _load(saving: true);
      return owner == _owner && !disposed;
    } catch (error) {
      if (owner == _owner && !disposed) {
        emit(
          PlanningState(
            month: state.month,
            data: state.data,
            error: error.toString(),
          ),
        );
      }
      return false;
    }
  }

  Future<bool> saveProfile(Json draft) => _save(
    (revision) => _repository.saveProfile({
      ...draft,
      'expected_revision': revision,
      'currency': _account!.currency,
    }),
    reportsChanged: true,
  );
  Future<bool> saveSchedule(String kind, Json draft, {String? id}) => _save(
    (revision) => _repository.saveSchedule(kind, {
      ...draft,
      'expected_revision': revision,
      'currency': _account!.currency,
    }, id: id),
    reportsChanged: kind == 'debts',
  );
  Future<bool> deleteSchedule(String kind, String id) => _save(
    (revision) => _repository.deleteSchedule(kind, id, revision),
    reportsChanged: kind == 'debts',
  );

  Future<bool> pay(String occurrenceId, Json draft) async {
    if (_account == null || state.saving || state.busy || disposed) {
      return false;
    }
    final fingerprint = jsonEncode([occurrenceId, draft]);
    if (_pendingFingerprint != fingerprint) {
      _pendingFingerprint = fingerprint;
      _pendingPayment = {
        ...draft,
        'operation_id': base64UrlEncode(
          List.generate(24, (_) => Random.secure().nextInt(256)),
        ).replaceAll('=', ''),
      };
    }
    final payment = Map<String, dynamic>.of(_pendingPayment!);
    final result = await _save(
      (revision) => _repository.pay(occurrenceId, {
        ...payment,
        'expected_revision': revision,
      }),
      reportsChanged: true,
    );
    if (result) {
      _pendingPayment = null;
      _pendingFingerprint = null;
    }
    return result;
  }

  Future<List<Entry>> expenses(DateTime month) async {
    final owner = _owner;
    if (_account == null || disposed) return [];
    final entries = await _repository.expenses(month);
    return owner == _owner && !disposed ? List.unmodifiable(entries) : [];
  }

  Future<bool> unlink(String occurrenceId, String transactionId) => _save(
    (revision) => _repository.unlink(occurrenceId, transactionId, revision),
    reportsChanged: true,
  );
}
