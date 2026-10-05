import '../core/model/contracts.dart';
import '../models/finance.dart';
import '../services/api.dart';
import 'offline_repository.dart';

class ApiAuthRepository implements AuthRepository {
  final Api _api;
  final OfflineRepository? offline;
  ApiAuthRepository(this._api, {this.offline});

  @override
  Future<Account> updateProfile(String name) async {
    final user = await _api.request('PUT', '/auth/me', body: {'name': name});
    await offline?.open(user);
    return Account.fromJson(user);
  }

  @override
  Future<Json> exportData() async => {
    ...await _api.request('GET', '/auth/me/export'),
    if (offline?.hasPending == true)
      'pending_device_transactions': [
        for (final op in offline!.state.operations)
          {
            'action': op['request']['action'],
            'transaction_id': op['request']['transaction_id'],
            'transaction': op['request']['transaction'],
            'status': op['status'],
            'created_at': op['created_at'],
          },
      ],
  };

  @override
  Future<Account?> restore() async {
    final cached = await offline?.restore();
    try {
      await _api.restore();
      if (_api.accessToken == null) {
        if (offline?.hasPending != true) await offline?.clear();
        return null;
      }
      final user = await _api.request('GET', '/auth/me');
      await offline?.open(user);
      return Account.fromJson(user);
    } on ApiException catch (e) {
      if ((e.network || (e.statusCode ?? 0) >= 500) &&
          cached != null &&
          _api.refreshToken != null) {
        return Account.fromJson(cached);
      }
      rethrow;
    }
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
        if (input.mode == 'register') ...{'name': input.name.trim()},
        if (input.mode == 'register' || input.mode == 'demo')
          'currency': input.currency,
      },
    );
    final account = Account.fromJson(session['user'] as Json);
    await offline?.open(session['user'] as Json);
    await _api.saveSession(session);
    return account;
  }

  @override
  Future<void> logout() async {
    if (offline?.hasPending == true) {
      throw ApiException(
        'Sync or resolve pending changes in Offline & sync before signing out.',
      );
    }
    try {
      if (_api.refreshToken != null) {
        await _api.request(
          'POST',
          '/auth/logout',
          body: {'refresh_token': _api.refreshToken},
        );
      }
    } on ApiException catch (e) {
      if (!e.network) rethrow;
    }
    await _api.clear();
    await offline?.clear();
  }

  @override
  Future<void> deleteAccount() async {
    await _api.request('DELETE', '/auth/me');
    await _api.clear();
    await offline?.clear();
  }
}

class ApiFinanceRepository
    implements
        OverviewRepository,
        TransactionRepository,
        BudgetRepository,
        CategoryRepository {
  final Api _api;
  final OfflineRepository? offline;
  ApiFinanceRepository(this._api, {this.offline});
  Future<Json> _read(String path) =>
      offline?.read(path) ?? _api.request('GET', path);

  @override
  Future<EntryPage> searchEntries(EntryFilter filter, int page) async {
    final query = Uri(
      queryParameters: {
        'start': dateOf(filter.start),
        'end': dateOf(filter.end),
        'q': filter.query,
        'page': '$page',
        'page_size': '50',
        if (filter.type != 'all') 'type': filter.type,
        if (filter.categoryId != null) 'category_id': filter.categoryId!,
        if (filter.minAmount != null) 'min_amount': '${filter.minAmount}',
        if (filter.maxAmount != null) 'max_amount': '${filter.maxAmount}',
      },
    ).query;
    final result = await _read('/transactions?$query');
    return EntryPage(
      (result['items'] as List)
          .map((item) => Entry.fromJson(item as Json))
          .toList(),
      result['total'] as int,
      cachedAt: result['_cached_at'] as String?,
    );
  }

  @override
  Future<MonthlySnapshot> loadMonth(DateTime month) async {
    final period = periodOf(month);
    final start = dateOf(DateTime(month.year, month.month));
    final end = dateOf(DateTime(month.year, month.month + 1, 0));
    final results = await Future.wait([
      _read('/reports/summary?month=$period'),
      _read('/categories'),
      _read('/budgets?period=$period'),
      _loadEntries(start, end),
    ]);
    return MonthlySnapshot(
      cachedAt:
          (results.map((r) => r['_cached_at']).whereType<String>().toList()
                ..sort())
              .firstOrNull,
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
    String? cachedAt;
    for (var page = 1; ; page++) {
      final result = await _read(
        '/transactions?start=$start&end=$end&page=$page&page_size=100',
      );
      final batch = (result['items'] as List).cast<Json>();
      items.addAll(batch);
      final at = result['_cached_at'] as String?;
      if (at != null && (cachedAt == null || at.compareTo(cachedAt) < 0)) {
        cachedAt = at;
      }
      if (items.length >= (result['total'] as int) || batch.isEmpty) break;
    }
    return {'items': items, '_cached_at': ?cachedAt};
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
    if (offline != null) {
      await offline!.enqueue(
        id == null ? 'create' : 'update',
        id: id,
        version: draft.expectedVersion,
        transaction: {
          'amount': draft.amount,
          'type': draft.type,
          'category_id': draft.categoryId,
          'date': dateOf(draft.date),
          'note': draft.note,
          'payment_method': draft.paymentMethod,
          'source': draft.source,
        },
      );
      return;
    }
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
  Future<void> deleteEntry(String id, {String? expectedVersion}) async {
    if (offline != null) {
      await offline!.enqueue('delete', id: id, version: expectedVersion);
      return;
    }
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
