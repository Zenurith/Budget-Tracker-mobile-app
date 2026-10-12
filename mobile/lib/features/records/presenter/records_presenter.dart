import 'dart:convert';
import 'dart:math';
import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';
import '../../../models/finance.dart';
import '../model/records_repository.dart';

class RecordsState {
  final Json balances, history, preview;
  final bool busy;
  final String? error, message;
  RecordsState({
    Json balances = const {},
    Json history = const {},
    Json preview = const {},
    this.busy = false,
    this.error,
    this.message,
  }) : balances = freezeJson(balances),
       history = freezeJson(history),
       preview = freezeJson(preview);
}

class RecordsPresenter extends Presenter<RecordsState> {
  final RecordsRepository repository;
  final CSVSource source;
  Account? _account;
  int _generation = 0;
  String? _contents, _fingerprint, _operation;
  RecordsPresenter(this.repository, this.source) : super(RecordsState());
  void setAccount(Account? account) {
    _generation++;
    _account = account;
    _contents = _fingerprint = _operation = null;
    emit(RecordsState());
  }

  Future<bool> _run(Future<void> Function(int generation) action) async {
    if (disposed || state.busy || _account == null) return false;
    final generation = _generation;
    emit(
      RecordsState(
        balances: state.balances,
        history: state.history,
        preview: state.preview,
        busy: true,
      ),
    );
    try {
      await action(generation);
      if (!_current(generation)) return false;
      emit(
        RecordsState(
          balances: state.balances,
          history: state.history,
          preview: state.preview,
          message: state.message,
        ),
      );
      return true;
    } catch (error) {
      if (_current(generation)) {
        emit(
          RecordsState(
            balances: state.balances,
            history: state.history,
            preview: state.preview,
            error: error.toString(),
            message: state.message,
          ),
        );
      }
      return false;
    }
  }

  bool _current(int generation) => !disposed && generation == _generation;
  String _id(Json payload) {
    final fingerprint = jsonEncode(payload);
    if (_fingerprint != fingerprint) {
      _fingerprint = fingerprint;
      _operation = base64UrlEncode(
        List.generate(24, (_) => Random.secure().nextInt(256)),
      ).replaceAll('=', '');
    }
    return _operation!;
  }

  Future<void> _load(
    int generation, {
    int balancePage = 1,
    int historyPage = 1,
  }) async {
    final balances = await repository.balances(balancePage);
    if (!_current(generation)) return;
    final history = await repository.history(historyPage);
    if (_current(generation)) {
      emit(
        RecordsState(
          balances: balances,
          history: history,
          preview: state.preview,
          busy: true,
          message: state.message,
        ),
      );
    }
  }

  Future<bool> reload({int balancePage = 1, int historyPage = 1}) =>
      _run((g) => _load(g, balancePage: balancePage, historyPage: historyPage));

  Future<bool> saveOpening(Json draft) => _run((g) async {
    final payload = {
      ...draft,
      'currency': _account!.currency,
      'expected_revision': state.balances['opening']?['revision'] ?? 0,
    };
    await repository.saveOpening({...payload, 'operation_id': _id(payload)});
    if (!_current(g)) return;
    _fingerprint = _operation = null;
    effect(const DataChanged());
    emit(
      RecordsState(
        balances: state.balances,
        history: state.history,
        preview: state.preview,
        busy: true,
        message: 'Opening balances saved. Reconcile protected cash separately.',
      ),
    );
    await _load(g);
  });

  Future<bool> pickCSV() async {
    var changed = false;
    final ok = await _run((g) async {
      final contents = await source.pick();
      if (!_current(g) || contents == null) return;
      // Clear the previous selection before validating a replacement file.
      _contents = null;
      emit(
        RecordsState(
          balances: state.balances,
          history: state.history,
          busy: true,
        ),
      );
      final preview = await repository.previewCSV(contents);
      if (!_current(g)) return;
      _contents = contents;
      changed = true;
      emit(
        RecordsState(
          balances: state.balances,
          history: state.history,
          preview: preview,
          busy: true,
        ),
      );
    });
    return ok && changed;
  }

  Future<bool> importCSV(Set<int> rows, Set<int> duplicates) => _run((g) async {
    if (_contents == null || rows.isEmpty) {
      throw StateError('Choose a CSV and select rows first.');
    }
    final payload = <String, dynamic>{
      'contents': _contents,
      'rows': rows.toList()..sort(),
      'allow_duplicates': duplicates.intersection(rows).toList()..sort(),
    };
    final result = await repository.importCSV({
      ...payload,
      'operation_id': _id(payload),
    });
    if (!_current(g)) return;
    _contents = _fingerprint = _operation = null;
    emit(
      RecordsState(
        balances: state.balances,
        history: state.history,
        busy: true,
        message: '${result['imported']} transactions imported.',
      ),
    );
    effect(const DataChanged());
    await _load(g);
  });

  Future<bool> undo(String id) => _run((g) async {
    await repository.undo(id);
    if (!_current(g)) return;
    effect(const DataChanged());
    emit(
      RecordsState(
        balances: state.balances,
        history: state.history,
        preview: state.preview,
        busy: true,
        message: 'Change undone. Review your cash reconciliation.',
      ),
    );
    await _load(g);
  });
}
