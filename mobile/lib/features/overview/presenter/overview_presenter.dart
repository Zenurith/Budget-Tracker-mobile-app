import '../../../core/model/contracts.dart';
import '../../../core/presentation/presenter.dart';
import '../../../models/finance.dart';

class OverviewState {
  final Account? account;
  final DateTime month;
  final MonthlySnapshot data;
  final bool busy, stale;
  final String? error;
  OverviewState({
    this.account,
    required this.month,
    MonthlySnapshot? data,
    this.busy = false,
    this.stale = false,
    this.error,
  }) : data = data ?? MonthlySnapshot();
}

class OverviewPresenter extends Presenter<OverviewState> {
  final OverviewRepository _repository;
  final DateTime Function() _now;
  int _request = 0;
  OverviewPresenter(this._repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(OverviewState(month: _month((now ?? DateTime.now)())));
  static DateTime _month(DateTime date) => DateTime(date.year, date.month);
  Json get summary => state.data.summary;
  List<FinanceCategory> get categories => state.data.categories;
  List<Entry> get entries => state.data.entries;
  List<Json> get budgets => state.data.budgets;
  Account? get user => state.account;
  DateTime get month => state.month;
  bool get busy => state.busy;
  String? get error => state.error;
  String get currency => state.account?.currency ?? '';
  String get period => periodOf(month);
  FinanceCategory category(String id) => categories.firstWhere(
    (c) => c.id == id,
    orElse: () => FinanceCategory.fromJson({
      'id': id,
      'name': 'Other',
      'type': 'expense',
      'icon': 'category',
      'color': '#9AA6A0',
    }),
  );

  List<Entry> filteredEntries({String search = '', String type = 'all', String? categoryId}) {
    final query = search.toLowerCase();
    return List.unmodifiable(entries.where((entry) =>
      (type == 'all' || entry.type == type) &&
      (categoryId == null || entry.categoryId == categoryId) &&
      (entry.note.toLowerCase().contains(query) || category(entry.categoryId).name.toLowerCase().contains(query))));
  }

  Future<void> setAccount(Account? account) async {
    _request++;
    emit(OverviewState(account: account, month: _month(_now())));
    if (account != null) await reload();
  }

  Future<void> changeMonth(int offset) =>
      showMonth(DateTime(month.year, month.month + offset));
  Future<void> showMonth(DateTime date) async {
    _request++;
    final next = _month(date);
    emit(
      OverviewState(
        account: user,
        month: next,
        data: next == month ? state.data : null,
      ),
    );
    await reload();
  }

  Future<void> reload() async {
    if (user == null || disposed) return;
    final request = ++_request;
    final account = user;
    final selected = month;
    final previous = state.data;
    emit(
      OverviewState(
        account: account,
        month: selected,
        data: previous,
        busy: true,
      ),
    );
    try {
      final result = await _repository.loadMonth(selected);
      if (request != _request || disposed) return;
      emit(OverviewState(account: account, month: selected, data: result));
    } catch (error) {
      if (request != _request || disposed) return;
      emit(
        OverviewState(
          account: account,
          month: selected,
          data: previous,
          stale: true,
          error: error.toString(),
        ),
      );
    }
  }
}
