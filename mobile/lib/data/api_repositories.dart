import '../core/model/contracts.dart';
import '../models/finance.dart';
import '../services/api.dart';

class ApiAuthRepository implements AuthRepository {
  final Api _api;
  ApiAuthRepository(this._api);

  @override
  Future<Account?> restore() async {
    await _api.restore();
    if (_api.accessToken == null) return null;
    return Account.fromJson(await _api.request('GET', '/auth/me'));
  }

  @override
  Future<Account> authenticate(AuthInput input) async {
    if (!const ['login', 'register', 'demo'].contains(input.mode)) {
      throw ArgumentError.value(input.mode, 'mode');
    }
    final session = await _api.request(
      'POST',
      '/auth/${input.mode}',
      body: {
        if (input.mode != 'demo') ...{
          'email': input.email.trim(),
          'password': input.password,
        },
        if (input.mode == 'register') ...{
          'name': input.name.trim(),
          'currency': input.currency,
        },
      },
    );
    final account = Account.fromJson(session['user'] as Json);
    await _api.saveSession(session);
    return account;
  }

  @override
  Future<void> logout() async {
    if (_api.refreshToken != null) {
      await _api.request(
        'POST',
        '/auth/logout',
        body: {'refresh_token': _api.refreshToken},
      );
    }
    await _api.clear();
  }

  @override
  Future<void> deleteAccount() async {
    await _api.request('DELETE', '/auth/me');
    await _api.clear();
  }
}

class ApiFinanceRepository
    implements
        OverviewRepository,
        TransactionRepository,
        BudgetRepository,
        CategoryRepository {
  final Api _api;
  ApiFinanceRepository(this._api);

  @override
  Future<MonthlySnapshot> loadMonth(DateTime month) async {
    final period = periodOf(month);
    final start = dateOf(DateTime(month.year, month.month));
    final end = dateOf(DateTime(month.year, month.month + 1, 0));
    final results = await Future.wait([
      _api.request('GET', '/reports/summary?month=$period'),
      _api.request('GET', '/categories'),
      _api.request('GET', '/budgets?period=$period'),
      _loadEntries(start, end),
    ]);
    return MonthlySnapshot(
      summary: results[0],
      categories: (results[1]['items'] as List)
          .map((item) => FinanceCategory.fromJson(item as Json))
          .toList(),
      budgets: (results[2]['items'] as List).cast<Json>(),
      entries: (results[3]['items'] as List)
          .map((item) => Entry.fromJson(item as Json))
          .toList(),
    );
  }

  Future<Json> _loadEntries(String start, String end) async {
    final items = <Json>[];
    for (var page = 1; ; page++) {
      final result = await _api.request(
        'GET',
        '/transactions?start=$start&end=$end&page=$page&page_size=100',
      );
      final batch = (result['items'] as List).cast<Json>();
      items.addAll(batch);
      if (items.length >= (result['total'] as int) || batch.isEmpty) break;
    }
    return {'items': items};
  }

  @override
  Future<ParsedEntry> parse(String text, DateTime referenceDate) async {
    final result = await _api.request(
      'POST',
      '/nlp/parse',
      body: {'text': text, 'reference_date': dateOf(referenceDate)},
    );
    return ParsedEntry(
      Entry.fromJson(result['transaction'] as Json),
      (result['warnings'] as List).cast<String>(),
    );
  }

  @override
  Future<void> saveEntry(EntryDraft draft, {String? id}) async {
    await _api.request(
      id == null ? 'POST' : 'PUT',
      id == null ? '/transactions' : '/transactions/${Uri.encodeComponent(id)}',
      body: {
        'amount': draft.amount,
        'type': draft.type,
        'category_id': draft.categoryId,
        'date': dateOf(draft.date),
        'note': draft.note,
        'payment_method': draft.paymentMethod,
        'source': draft.source,
      },
    );
  }

  @override
  Future<void> deleteEntry(String id) async {
    await _api.request('DELETE', '/transactions/${Uri.encodeComponent(id)}');
  }

  @override
  Future<void> saveBudget(BudgetDraft draft) async {
    await _api.request(
      'POST',
      '/budgets',
      body: {
        'period': draft.period,
        'category_id': draft.categoryId,
        'limit_amount': draft.limitAmount,
        'alert_threshold': draft.alertThreshold,
      },
    );
  }

  @override
  Future<void> deleteBudget(String id) async {
    await _api.request('DELETE', '/budgets/${Uri.encodeComponent(id)}');
  }

  @override
  Future<void> saveCategory(CategoryDraft draft, {String? id}) async {
    await _api.request(
      id == null ? 'POST' : 'PUT',
      id == null ? '/categories' : '/categories/${Uri.encodeComponent(id)}',
      body: {
        'name': draft.name,
        'type': draft.type,
        'icon': draft.icon,
        'color': draft.color,
      },
    );
  }

  @override
  Future<void> deleteCategory(String id) async {
    await _api.request('DELETE', '/categories/${Uri.encodeComponent(id)}');
  }
}
