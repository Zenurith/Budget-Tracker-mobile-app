import 'dart:convert';
import 'dart:math';
import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';
import '../../../models/finance.dart';
import '../model/funding_repository.dart';

class FundingState {
  final Json data;
  final List<Json> events;
  final bool busy, saving, stale;
  final String? error;
  final int page, total;
  FundingState({
    Json data = const {},
    List<Json> events = const [],
    this.busy = false,
    this.saving = false,
    this.stale = false,
    this.error,
    this.page = 0,
    this.total = 0,
  }) : data = freezeJson(data),
       events = List.unmodifiable(events.map(freezeJson));
  bool get editable => data.isNotEmpty && !busy && !saving && !stale;
}

class FundingPresenter extends Presenter<FundingState> {
  final FundingRepository _repository;
  Account? _account;
  int _request = 0, _owner = 0;
  String? _fingerprint;
  Json? _pending;
  FundingPresenter(this._repository) : super(FundingState());
  void setAccount(Account? account) {
    _owner++;
    _request++;
    _account = account;
    _fingerprint = null;
    _pending = null;
    emit(FundingState());
  }

  FundingState copy({
    bool busy = false,
    bool saving = false,
    bool? stale,
    String? error,
  }) => FundingState(
    data: state.data,
    events: state.events,
    page: state.page,
    total: state.total,
    busy: busy,
    saving: saving,
    stale: stale ?? state.stale,
    error: error,
  );
  void invalidate({int? planningRevision}) {
    if (state.data.isEmpty ||
        (planningRevision != null &&
            state.data['planning_revision'] == planningRevision)) {
      return;
    }
    _request++;
    emit(copy(stale: true, saving: state.saving));
  }

  Future<void> reload() async {
    if (_account == null || disposed || state.saving) return;
    await _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    emit(copy(busy: true));
    try {
      final data = await _repository.load();
      if (request != _request || disposed) return;
      // Cash is usable even when history cannot be fetched; history has a separate retry.
      emit(FundingState(data: data));
      await loadEvents(reset: true);
    } catch (e) {
      if (request == _request && !disposed) {
        emit(copy(stale: true, error: e.toString()));
      }
    }
  }

  Future<void> loadEvents({bool reset = false}) async {
    if (_account == null || disposed || state.busy || state.saving) return;
    final request = ++_request;
    final page = reset ? 1 : state.page + 1;
    emit(copy(busy: true));
    try {
      final result = await _repository.events(page);
      if (request != _request || disposed) return;
      final items = <String, Json>{
        if (!reset)
          for (final e in state.events) e['id'] as String: e,
        for (final e in (result['items'] as List).cast<Json>())
          e['id'] as String: e,
      };
      emit(
        FundingState(
          data: state.data,
          events: items.values.toList(),
          page: page,
          total: result['total'] as int,
          stale: state.stale,
        ),
      );
    } catch (e) {
      if (request == _request && !disposed) emit(copy(error: e.toString()));
    }
  }

  Json reviewed(Json draft) => {
    ...draft,
    'currency': _account!.currency,
    'expected_revision': state.data['revision'],
    'expected_planning_revision': state.data['planning_revision'],
  };
  Future<bool> _save(
    Future<Json> Function() operation, {
    bool refresh = false,
  }) async {
    if (_account == null || disposed || !state.editable) return false;
    final owner = _owner;
    final request = ++_request;
    emit(copy(saving: true));
    try {
      final result = await operation();
      if (owner != _owner || disposed) return false;
      if (refresh) {
        await _load();
      } else {
        emit(
          FundingState(
            data: {
              ...result,
              if (!result.containsKey('categories'))
                'categories': state.data['categories'] ?? [],
            },
            stale: request != _request,
            events: state.events,
            page: state.page,
            total: state.total,
          ),
        );
      }
      if (owner == _owner && !disposed) effect(const DataChanged());
      return owner == _owner && !disposed;
    } catch (e) {
      if (owner == _owner && !disposed) emit(copy(error: e.toString()));
      return false;
    }
  }

  Future<bool> saveSnapshot(Json draft) =>
      _save(() => _repository.saveSnapshot(reviewed(draft)), refresh: true);
  Future<bool> savePlan(Json draft) =>
      _save(() => _repository.savePlan(reviewed(draft)), refresh: true);
  Future<bool> saveGoal(Json draft, {String? id}) => _save(
    () => _repository.saveGoal({
      ...draft,
      'currency': _account!.currency,
      'expected_revision': state.data['revision'],
    }, id: id),
    refresh: true,
  );
  Future<bool> deleteGoal(String id) => _save(
    () => _repository.deleteGoal(id, state.data['revision'] as int),
    refresh: true,
  );
  Future<bool> move(String kind, Json draft) async {
    if (_account == null || disposed || !state.editable) return false;
    final amount = draft['amount'];
    if (amount is! int || amount <= 0 || amount > 100000000000) {
      emit(copy(error: 'Enter a positive amount.'));
      return false;
    }
    final fingerprint = jsonEncode([kind, draft]);
    if (fingerprint != _fingerprint) {
      _fingerprint = fingerprint;
      _pending = {
        ...draft,
        'operation_id': base64UrlEncode(
          List.generate(24, (_) => Random.secure().nextInt(256)),
        ).replaceAll('=', ''),
      };
    }
    final pending = Map<String, dynamic>.of(_pending!);
    final result = await _save(
      () => _repository.move(kind, reviewed(pending)),
      refresh: true,
    );
    if (result) {
      _fingerprint = null;
      _pending = null;
    }
    return result;
  }

  Future<List<Json>> purchaseExpenses(String date, int amount) async {
    if (_account == null || disposed) return [];
    final owner = _owner;
    final result = await _repository.expenses(date, amount);
    if (owner != _owner || disposed) return [];
    return (result['items'] as List)
        .cast<Json>()
        .where(
          (e) =>
              e['wishlist_purchase_id'] == null &&
              e['commitment_occurrence_id'] == null,
        )
        .map(freezeJson)
        .toList(growable: false);
  }

  Future<bool> saveWishlist(Json draft, {String? id}) => _save(
    () => _repository.saveWishlist({
      ...draft,
      'currency': _account!.currency,
      'expected_revision': state.data['revision'],
    }, id: id),
  );
  Future<bool> deleteWishlist(String id) => _save(
    () => _repository.deleteWishlist(id, state.data['revision'] as int),
  );

  Future<bool> recordPurchase(String id, Json draft) =>
      _record(id, 'purchase', draft);
  Future<bool> adjustPurchase(String id, String kind, Json draft) =>
      _record(id, kind, draft);
  Future<bool> _record(String id, String kind, Json draft) async {
    if (_account == null || disposed || !state.editable) return false;
    final fingerprint = jsonEncode([id, kind, draft]);
    if (_fingerprint != fingerprint) {
      _fingerprint = fingerprint;
      _pending = {
        ...draft,
        'operation_id': base64UrlEncode(
          List.generate(24, (_) => Random.secure().nextInt(256)),
        ).replaceAll('=', ''),
      };
    }
    final pending = Map<String, dynamic>.of(_pending!);
    final ok = await _save(() {
      final payload = reviewed(pending);
      if (kind == 'purchase') return _repository.purchase(id, payload);
      payload.remove('expected_planning_revision');
      return _repository.adjustPurchase(id, kind, payload);
    }, refresh: true);
    if (ok) {
      _pending = null;
      _fingerprint = null;
    }
    return ok;
  }
}
