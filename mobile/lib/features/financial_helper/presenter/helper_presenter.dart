import 'dart:convert';
import 'dart:math';
import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';
import '../../../models/finance.dart';
import '../model/helper_repository.dart';
import '../model/helper_input_rules.dart';

class HelperState {
  final Json baseline, scenario, assumptions;
  final List<Json> snapshots;
  final int page, total;
  final bool busy, saving, stale;
  final String? error;
  HelperState({
    Json baseline = const {},
    Json scenario = const {},
    Json assumptions = const {},
    List<Json> snapshots = const [],
    this.page = 0,
    this.total = 0,
    this.busy = false,
    this.saving = false,
    this.stale = false,
    this.error,
  }) : baseline = freezeJson(baseline),
       scenario = freezeJson(scenario),
       assumptions = freezeJson(assumptions),
       snapshots = List.unmodifiable(snapshots.map(freezeJson));
  bool get hasMore => snapshots.length < total;
  bool get canSave => baseline.isNotEmpty && !busy && !saving && !stale;
}

class HelperPresenter extends Presenter<HelperState> {
  final HelperRepository _repository;
  Account? _account;
  int _request = 0;
  Json? _pendingSave;
  String? _pendingFingerprint;
  HelperPresenter(this._repository) : super(HelperState());

  void setAccount(Account? account) {
    _request++;
    _account = account;
    _pendingSave = null;
    _pendingFingerprint = null;
    emit(HelperState());
  }

  void invalidate(int revision) {
    if (state.baseline.isEmpty ||
        state.baseline['source_revision'] == revision) {
      return;
    }
    _request++;
    emit(_copy(stale: true));
  }

  HelperState _copy({
    bool busy = false,
    bool saving = false,
    bool? stale,
    String? error,
  }) => HelperState(
    baseline: state.baseline,
    scenario: state.scenario,
    assumptions: state.assumptions,
    snapshots: state.snapshots,
    page: state.page,
    total: state.total,
    busy: busy,
    saving: saving,
    stale: stale ?? state.stale,
    error: error,
  );

  Future<void> reload() async {
    if (_account == null || disposed || state.saving) return;
    final request = ++_request;
    emit(_copy(busy: true));
    try {
      final baseline = await _repository.calculate();
      final history = await _repository.snapshots(1);
      if (request != _request || disposed) return;
      emit(
        HelperState(
          baseline: baseline,
          snapshots: (history['items'] as List).cast<Json>(),
          page: 1,
          total: history['total'] as int,
        ),
      );
    } catch (e) {
      if (request == _request && !disposed) {
        emit(_copy(stale: true, error: e.toString()));
      }
    }
  }

  Future<bool> preview(Json assumptions, String effectiveDate) async {
    if (_account == null ||
        disposed ||
        state.busy ||
        state.saving ||
        state.stale ||
        state.baseline.isEmpty) {
      return false;
    }
    final request = ++_request;
    final validation = HelperInputRules.validate(assumptions, effectiveDate);
    if (validation != null) {
      emit(_copy(error: validation));
      return false;
    }
    final draft = freezeJson({...assumptions, 'currency': _account!.currency});
    emit(_copy(busy: true));
    try {
      final result = await _repository.scenario({
        'expected_revision': state.baseline['source_revision'],
        'effective_date': effectiveDate,
        'assumptions': draft,
      });
      if (request != _request || disposed) return false;
      emit(
        HelperState(
          baseline: result['baseline'] as Json,
          scenario: result['scenario'] as Json,
          assumptions: draft,
          snapshots: state.snapshots,
          page: state.page,
          total: state.total,
        ),
      );
      return true;
    } catch (e) {
      if (request == _request && !disposed) emit(_copy(error: e.toString()));
      return false;
    }
  }

  Future<void> discardScenario() => reload();

  Future<bool> save(String name, {bool scenario = false}) async {
    if (_account == null || disposed || !state.canSave) return false;
    final result = scenario ? state.scenario : state.baseline;
    if (result.isEmpty || name.trim().isEmpty || name.trim().length > 80) {
      return false;
    }
    final draft = <String, dynamic>{
      'name': name.trim(),
      'expected_revision': result['source_revision'],
      'effective_date': result['effective_date'],
      if (scenario) 'assumptions': state.assumptions,
    };
    final fingerprint = jsonEncode(draft);
    if (_pendingFingerprint != fingerprint) {
      _pendingFingerprint = fingerprint;
      _pendingSave = {
        ...draft,
        'operation_id': base64UrlEncode(
          List.generate(24, (_) => Random.secure().nextInt(256)),
        ).replaceAll('=', ''),
      };
    }
    final request = ++_request;
    emit(_copy(saving: true));
    try {
      final saved = await _repository.saveSnapshot(_pendingSave!);
      if (request != _request || disposed) return false;
      _pendingSave = null;
      _pendingFingerprint = null;
      // Show the committed response without requiring another network request.
      final exists = state.snapshots.any((r) => r['id'] == saved['id']);
      emit(
        HelperState(
          baseline: state.baseline,
          scenario: state.scenario,
          assumptions: state.assumptions,
          snapshots: [
            saved,
            ...state.snapshots.where((r) => r['id'] != saved['id']),
          ],
          page: state.page,
          total: state.total + (exists ? 0 : 1),
        ),
      );
      return true;
    } catch (e) {
      if (request == _request && !disposed) emit(_copy(error: e.toString()));
      return false;
    }
  }

  Future<void> loadMore() async {
    if (_account == null ||
        disposed ||
        state.busy ||
        state.saving ||
        !state.hasMore) {
      return;
    }
    final request = ++_request;
    emit(_copy(busy: true));
    try {
      final history = await _repository.snapshots(state.page + 1);
      if (request != _request || disposed) return;
      final merged = {
        for (final item in state.snapshots) item['id']: item,
        for (final item in (history['items'] as List).cast<Json>())
          item['id']: item,
      };
      emit(
        HelperState(
          baseline: state.baseline,
          scenario: state.scenario,
          assumptions: state.assumptions,
          snapshots: merged.values.toList(),
          page: history['page'] as int,
          total: history['total'] as int,
          stale: state.stale,
        ),
      );
    } catch (e) {
      if (request == _request && !disposed) emit(_copy(error: e.toString()));
    }
  }
}
