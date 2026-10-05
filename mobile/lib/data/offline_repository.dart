import 'dart:async';
import 'dart:convert';
import 'dart:math';
import '../models/finance.dart';
import '../features/sync/model/sync_repository.dart';
import '../services/api.dart';

/// One owner and server per encrypted document. Queue writes precede network I/O.
class OfflineRepository implements SyncRepository {
  final Api api;
  final OfflinePersistence persistence;
  final DateTime Function() now;
  OfflineRepository(this.api, this.persistence, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  Json _document = {};
  int _generation = 0;
  Future<void> _tail = Future.value();
  final _states = StreamController<SyncState>.broadcast(sync: true);
  @override
  SyncState state = SyncState();
  @override
  Stream<SyncState> get states => _states.stream;
  String get _server => api.baseUrl.isEmpty ? Api.defaultUrl : api.baseUrl;
  List<Json> get _operations =>
      (_document['operations'] as List? ?? []).cast<Json>();
  bool get hasPending => _operations.isNotEmpty;
  Json _copy(Json value) => jsonDecode(jsonEncode(value)) as Json;
  String _id() => base64UrlEncode(
    List.generate(24, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');
  void _check(int generation) {
    if (generation != _generation || _document['account'] == null) {
      throw ApiException('The signed-in account changed.');
    }
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _emit({bool? offline, bool busy = false, String? error}) {
    state = SyncState(
      operations: _operations,
      offline: offline ?? state.offline,
      busy: busy,
      error: error,
    );
    _states.add(state);
  }

  Future<void> _commit(Json next, int generation) async {
    _check(generation);
    await persistence.write(jsonEncode(next));
    _check(generation);
    _document = next;
  }

  Future<Json?> restore() => _serial(() async {
    final saved = await persistence.read();
    if (saved == null) return null;
    final doc = jsonDecode(saved) as Json;
    if (doc['schema'] != 1 || doc['server'] != _server) return null;
    _document = doc;
    _generation++;
    _emit(offline: true);
    return _copy(doc['account'] as Json);
  });

  Future<void> open(Json account) => _serial(() async {
    if (_document.isEmpty) {
      final saved = await persistence.read();
      if (saved != null) {
        final doc = jsonDecode(saved) as Json;
        if (doc['schema'] == 1 && doc['server'] == _server) _document = doc;
      }
    }
    if (_document['account']?['id'] != account['id']) {
      if (hasPending) {
        throw ApiException(
          'Sign back into the previous account and sync its pending changes before switching accounts.',
        );
      }
      _document = {
        'schema': 1,
        'server': _server,
        'cache': <String, dynamic>{},
        'operations': <Json>[],
      };
    }
    _generation++;
    _document['account'] = _copy(account);
    await persistence.write(jsonEncode(_document));
    _emit(offline: false);
  });

  Future<void> clear() {
    _generation++;
    _document = {};
    _emit(offline: false);
    return _serial(() => persistence.write(null));
  }

  void guard(String path) {
    if (hasPending &&
        (path.startsWith('/funding') ||
            path.startsWith('/wishlist') ||
            path.startsWith('/goals'))) {
      throw ApiException(
        'Sync or resolve pending transactions before reviewing or changing protected funding.',
      );
    }
  }

  bool _retryable(ApiException e) =>
      e.network ||
      (e.statusCode ?? 0) >= 500 ||
      e.statusCode == 429 ||
      e.statusCode == 408;

  Future<Json> read(String path) async {
    final generation = _generation;
    _check(generation);
    // Financial authorization endpoints deliberately never use this cache.
    if (![
      '/transactions',
      '/categories',
      '/budgets',
      '/reports/summary',
    ].contains(Uri.parse(path).path)) {
      throw ArgumentError('Unsupported offline cache path');
    }
    try {
      final result = await api.request('GET', path);
      _check(generation);
      await _serial(() async {
        _check(generation);
        final next = _copy(_document);
        final cache = next['cache'] as Json;
        cache.remove(path);
        cache[path] = {'at': now().toUtc().toIso8601String(), 'data': result};
        // Recent queries only; never evict queued work to fit the cache.
        while (cache.length > 40 ||
            (cache.isNotEmpty &&
                utf8.encode(jsonEncode(cache)).length > 750000)) {
          cache.remove(cache.keys.first);
        }
        await _commit(next, generation);
      });
      return result;
    } on ApiException catch (e) {
      _check(generation);
      if (!_retryable(e)) rethrow;
      _emit(offline: true, busy: state.busy);
      final cached = _document['cache']?[path] as Json?;
      if (cached == null) rethrow;
      return {..._copy(cached['data'] as Json), '_cached_at': cached['at']};
    }
  }

  Future<void> enqueue(
    String action, {
    String? id,
    String? version,
    Json? transaction,
  }) async {
    final generation = _generation;
    _check(generation);
    await _serial(() async {
      _check(generation);
      if (id != null &&
          _operations.any((op) => op['request']['transaction_id'] == id)) {
        throw ApiException(
          'Resolve the pending change for this transaction in Offline & sync first.',
        );
      }
      if (action != 'create' && version == null) {
        throw ApiException(
          'Refresh this transaction before editing or deleting it.',
        );
      }
      if (_operations.length >= 100) {
        throw ApiException(
          'Sync or resolve the 100 pending changes before adding more.',
        );
      }
      final next = _copy(_document);
      Json? before;
      if (id != null) {
        for (final cached in (next['cache'] as Json).values) {
          for (final entry in cached['data']['items'] as List? ?? []) {
            if (entry['id'] == id && entry['version'] == version) {
              before = Map<String, dynamic>.from(entry);
            }
          }
        }
      }
      (next['operations'] as List).add({
        'before': ?before,
        'request': {
          'operation_id': _id(),
          'action': action,
          'transaction_id': ?id,
          'expected_version': ?version,
          'transaction': ?transaction,
        },
        'status': 'pending',
        'created_at': now().toUtc().toIso8601String(),
      });
      await _commit(next, generation);
      _emit();
    });
    // Once durably queued, errors belong to the sync screen, not a second save.
    await synchronize();
  }

  @override
  Future<void> synchronize() {
    final generation = _generation;
    return _serial(() async {
      _check(generation);
      _emit(busy: true);
      try {
        final account = await api.request('GET', '/auth/me');
        _check(generation);
        if (account['id'] != _document['account']['id']) {
          throw ApiException(
            'Sign in to the account that owns these pending changes.',
          );
        }
        _emit(offline: false, busy: true);
        for (final original in List<Json>.of(_operations)) {
          if (original['status'] != 'pending') continue;
          final request = original['request'] as Json;
          try {
            await api.request('POST', '/transactions/sync', body: request);
            _check(generation);
            final next = _copy(_document);
            (next['operations'] as List).removeWhere(
              (op) => op['request']['operation_id'] == request['operation_id'],
            );
            // Old cached totals/records stay inspectable, but are labelled stale until refetched.
            await _commit(next, generation);
          } on ApiException catch (e) {
            _check(generation);
            if (_retryable(e) || e.statusCode == 401 || e.statusCode == 403) {
              rethrow;
            }
            final next = _copy(_document);
            final op = (next['operations'] as List).firstWhere(
              (op) => op['request']['operation_id'] == request['operation_id'],
            );
            op['status'] = 'conflict';
            op['error'] = e.toString();
            await _commit(next, generation);
          }
        }
        _emit();
      } catch (e) {
        if (generation == _generation) {
          _emit(offline: true, error: e.toString());
        }
      }
    });
  }

  @override
  Future<void> review(String operationId) {
    final generation = _generation;
    return _serial(() async {
      _check(generation);
      final original = _operations.firstWhere(
        (op) => op['request']['operation_id'] == operationId,
      );
      final id = original['request']['transaction_id'];
      if (original['status'] != 'conflict' || id == null) return;
      Json? server;
      try {
        server = await api.request(
          'GET',
          '/transactions/${Uri.encodeComponent(id)}',
        );
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
      }
      _check(generation);
      final next = _copy(_document);
      final op = (next['operations'] as List).firstWhere(
        (op) => op['request']['operation_id'] == operationId,
      );
      op['server'] = server;
      op['reviewed'] = true;
      await _commit(next, generation);
      _emit();
    });
  }

  @override
  Future<void> resolve(String operationId, {required bool useLocal}) async {
    final generation = _generation;
    await _serial(() async {
      _check(generation);
      final next = _copy(_document);
      final operations = next['operations'] as List;
      final op = operations.firstWhere(
        (op) => op['request']['operation_id'] == operationId,
      );
      // A timed-out request may already have committed; it must be replayed first.
      if (op['status'] != 'conflict') {
        throw ApiException(
          'Retry synchronization to determine whether this change was saved before resolving it.',
        );
      }
      if (useLocal) {
        final server = op['server'] as Json?;
        if (op['reviewed'] != true ||
            server == null ||
            server['wishlist_purchase_id'] != null ||
            server['commitment_occurrence_id'] != null) {
          throw ApiException(
            'Review an existing unlinked server transaction before keeping your change.',
          );
        }
        op['request']['operation_id'] = _id();
        op['request']['expected_version'] = server['version'];
        op['status'] = 'pending';
        op.remove('server');
        op.remove('reviewed');
        op.remove('error');
      } else {
        operations.remove(op);
      }
      await _commit(next, generation);
      _emit();
    });
    if (useLocal) await synchronize();
  }
}
