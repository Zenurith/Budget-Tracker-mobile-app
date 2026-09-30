import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';
import '../../../models/finance.dart';

class HistoryState {
  final EntryFilter filter;
  final List<Entry> entries;
  final int total, page;
  final bool busy;
  final String? error;
  HistoryState({
    required this.filter,
    List<Entry> entries = const [],
    this.total = 0,
    this.page = 0,
    this.busy = false,
    this.error,
  }) : entries = List.unmodifiable(entries);
}

class HistoryPresenter extends Presenter<HistoryState> {
  final TransactionRepository _repository;
  int _request = 0;
  bool _signedIn = false;
  HistoryPresenter(this._repository, {DateTime Function()? now})
    : super(HistoryState(filter: monthFilter((now ?? DateTime.now)())));

  static EntryFilter monthFilter(DateTime month) => EntryFilter(
    start: DateTime(month.year, month.month),
    end: DateTime(month.year, month.month + 1, 0),
  );

  Future<void> setAccount(Account? account, DateTime month) async {
    _request++;
    _signedIn = account != null;
    emit(HistoryState(filter: monthFilter(month)));
    if (_signedIn) await apply(state.filter);
  }

  Future<void> showMonth(DateTime month) => apply(
    EntryFilter(
      start: DateTime(month.year, month.month),
      end: DateTime(month.year, month.month + 1, 0),
      query: state.filter.query,
      type: state.filter.type,
      categoryId: state.filter.categoryId,
      minAmount: state.filter.minAmount,
      maxAmount: state.filter.maxAmount,
    ),
  );
  Future<void> reload() => apply(state.filter);

  Future<void> apply(EntryFilter filter) async {
    if (!_signedIn || disposed) return;
    final request = ++_request;
    final invalid =
        filter.start.isAfter(filter.end) ||
        (filter.minAmount != null && filter.minAmount! < 0) ||
        (filter.maxAmount != null && filter.maxAmount! < 0) ||
        (filter.minAmount != null &&
            filter.maxAmount != null &&
            filter.minAmount! > filter.maxAmount!);
    if (invalid) {
      emit(
        HistoryState(
          filter: state.filter,
          entries: state.entries,
          total: state.total,
          page: state.page,
          error: 'Check the date and amount ranges.',
        ),
      );
      return;
    }
    emit(HistoryState(filter: filter, busy: true));
    try {
      final result = await _repository.searchEntries(filter, 1);
      if (request != _request || disposed) return;
      emit(
        HistoryState(
          filter: filter,
          entries: result.entries,
          total: result.total,
          page: 1,
        ),
      );
    } catch (error) {
      if (request == _request && !disposed) {
        emit(HistoryState(filter: filter, error: error.toString()));
      }
    }
  }

  Future<void> loadMore() async {
    if (!_signedIn ||
        disposed ||
        state.busy ||
        state.entries.length >= state.total) {
      return;
    }
    final previous = state;
    final request = ++_request;
    emit(
      HistoryState(
        filter: previous.filter,
        entries: previous.entries,
        total: previous.total,
        page: previous.page,
        busy: true,
      ),
    );
    try {
      final result = await _repository.searchEntries(
        previous.filter,
        previous.page + 1,
      );
      if (request != _request || disposed) return;
      final entries = {
        for (final entry in [...previous.entries, ...result.entries])
          entry.id: entry,
      };
      emit(
        HistoryState(
          filter: previous.filter,
          entries: entries.values.toList(),
          total: result.total,
          page: previous.page + 1,
        ),
      );
    } catch (error) {
      if (request == _request && !disposed) {
        emit(
          HistoryState(
            filter: previous.filter,
            entries: previous.entries,
            total: previous.total,
            page: previous.page,
            error: error.toString(),
          ),
        );
      }
    }
  }
}
