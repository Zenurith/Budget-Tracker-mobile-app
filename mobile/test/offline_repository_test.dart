import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pocketwise/data/api_repositories.dart';
import 'package:pocketwise/core/model/contracts.dart';
import 'package:pocketwise/data/offline_repository.dart';
import 'package:pocketwise/features/sync/model/sync_repository.dart';
import 'package:pocketwise/models/finance.dart';
import 'package:pocketwise/services/api.dart';

class MemoryPersistence implements OfflinePersistence {
  String? value;
  bool fail = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? next) async {
    if (fail) throw StateError('Device storage unavailable');
    value = next;
  }
}

const account = {
  'id': 'owner',
  'name': 'Alex',
  'email': 'a@example.com',
  'currency': 'EUR',
};
const draft = {
  'amount': 100,
  'type': 'expense',
  'category_id': 'food',
  'date': '2026-10-05',
  'note': 'Lunch',
  'payment_method': 'Cash',
  'source': 'manual',
};
http.Response response(Object data, [int status = 200]) =>
    http.Response(jsonEncode(data), status);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'expired sessions preserve queued work until same-owner sign in',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'refresh_token': 'expired-session',
      });
      var expired = false;
      final disk = MemoryPersistence();
      final api = Api(
        client: MockClient((request) async {
          if (request.url.path == '/auth/login') {
            return response({
              'user': account,
              'access_token': 'fresh',
              'refresh_token': 'fresh-refresh',
            });
          }
          if (expired) {
            return response({
              'error': {'message': 'Please sign in again'},
            }, 401);
          }
          throw http.ClientException('offline');
        }),
      );
      addTearDown(api.client.close);
      var repo = OfflineRepository(api, disk);
      await repo.open(account);
      await repo.enqueue('create', transaction: draft);
      expired = true;
      repo = OfflineRepository(api, disk);
      final auth = ApiAuthRepository(api, offline: repo);
      await expectLater(auth.restore(), throwsA(isA<ApiException>()));
      expect(repo.state.operations, hasLength(1));
      await auth.authenticate(
        const AuthInput(
          mode: 'login',
          email: 'a@example.com',
          password: 'password',
        ),
      );
      expect(repo.state.operations, hasLength(1));
      expect(api.accessToken, 'fresh');
    },
  );
  test(
    'offline startup restores only the cached account with a retained session; sign out clears device data',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'refresh_token': 'saved-session',
      });
      final disk = MemoryPersistence();
      final api = Api(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      addTearDown(api.client.close);
      await OfflineRepository(api, disk).open(account);
      final repo = OfflineRepository(api, disk);
      final auth = ApiAuthRepository(api, offline: repo);
      expect((await auth.restore())!.id, 'owner');
      expect(repo.state.offline, true);
      await auth.logout();
      expect(disk.value, isNull);
      expect(await api.storage.read(key: 'refresh_token'), isNull);
    },
  );
  test(
    'pending changes block sign out and are included in personal export',
    () async {
      final api = Api(
        client: MockClient((request) async {
          if (request.url.path == '/auth/me/export') {
            return response({'transactions': []});
          }
          throw http.ClientException('offline');
        }),
      );
      addTearDown(api.client.close);
      final disk = MemoryPersistence();
      final repo = OfflineRepository(api, disk);
      await repo.open(account);
      await repo.enqueue('create', transaction: draft);
      final auth = ApiAuthRepository(api, offline: repo);
      await expectLater(auth.logout(), throwsA(isA<ApiException>()));
      final exported = await auth.exportData();
      expect(
        exported['pending_device_transactions'][0]['transaction']['note'],
        'Lunch',
      );
      expect(repo.state.operations, hasLength(1));
    },
  );
  test(
    'recent cache survives restart, labels age and never hides authorization errors',
    () async {
      final disk = MemoryPersistence();
      var status = 200;
      final api = Api(
        client: MockClient((req) async {
          if (status == 0) throw http.ClientException('offline');
          return status == 200
              ? response({
                  'items': [draft],
                  'total': 1,
                })
              : response({
                  'error': {'message': 'Sign in'},
                }, status);
        }),
      );
      addTearDown(api.client.close);
      var repo = OfflineRepository(
        api,
        disk,
        now: () => DateTime.utc(2026, 10, 5),
      );
      await repo.open(account);
      await repo.read('/transactions?page=1');
      status = 0;
      repo = OfflineRepository(api, disk);
      expect((await repo.restore())!['id'], 'owner');
      final cached = await repo.read('/transactions?page=1');
      expect(cached['_cached_at'], '2026-10-05T00:00:00.000Z');
      expect(cached['items'], [draft]);
      expect(repo.state.offline, true);
      expect(() => repo.read('/wishlist'), throwsArgumentError);
      expect(
        () => repo.read('/transactions?page=2'),
        throwsA(isA<ApiException>()),
      );
      status = 401;
      await expectLater(
        repo.read('/transactions?page=1'),
        throwsA(isA<ApiException>()),
      );
      await repo.open({...account, 'id': 'other'});
      status = 0;
      await expectLater(
        repo.read('/transactions?page=1'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'a lost response and process restart replay the same operation without a second expense',
    () async {
      final disk = MemoryPersistence();
      var loseResponse = true;
      final saved = <String, Json>{};
      final keys = <String>[];
      final api = Api(
        client: MockClient((req) async {
          if (req.url.path == '/auth/me') return response(account);
          final body = jsonDecode(req.body) as Json;
          final key = body['operation_id'] as String;
          keys.add(key);
          saved.putIfAbsent(
            key,
            () => {
              'transaction': {...draft, 'id': 'one', 'version': 'version'},
            },
          );
          if (loseResponse) {
            throw http.ClientException('response lost after commit');
          }
          return response(saved[key]!);
        }),
      );
      addTearDown(api.client.close);
      var repo = OfflineRepository(api, disk);
      await repo.open(account);
      await repo.enqueue('create', transaction: draft);
      expect(repo.state.operations, hasLength(1));
      expect(repo.state.offline, true);
      expect(() => repo.guard('/wishlist'), throwsA(isA<ApiException>()));
      await expectLater(
        repo.resolve(keys.single, useLocal: false),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        repo.open({...account, 'id': 'other'}),
        throwsA(isA<ApiException>()),
      );
      repo = OfflineRepository(api, disk);
      await repo.restore();
      loseResponse = false;
      await repo.synchronize();
      expect(keys, [keys.first, keys.first]);
      expect(saved, hasLength(1));
      expect(repo.state.operations, isEmpty);
      expect(repo.state.offline, false);
      expect(jsonDecode(disk.value!)['operations'], isEmpty);
    },
  );

  test(
    'conflict resolution requires a reviewed version and uses a new operation key',
    () async {
      final disk = MemoryPersistence();
      final requests = <Json>[];
      final api = Api(
        client: MockClient((req) async {
          if (req.url.path == '/auth/me') return response(account);
          if (req.method == 'GET') {
            return response({
              ...draft,
              'id': 'entry',
              'amount': 200,
              'version': 'new',
            });
          }
          final body = jsonDecode(req.body) as Json;
          requests.add(body);
          return body['expected_version'] == 'new'
              ? response({'transaction': draft})
              : response({
                  'error': {'message': 'Changed on server'},
                }, 409);
        }),
      );
      addTearDown(api.client.close);
      final repo = OfflineRepository(api, disk);
      await repo.open(account);
      await repo.enqueue(
        'update',
        id: 'entry',
        version: 'old',
        transaction: draft,
      );
      final id = requests.first['operation_id'];
      expect(repo.state.operations.single['status'], 'conflict');
      await expectLater(
        repo.resolve(id, useLocal: true),
        throwsA(isA<ApiException>()),
      );
      await repo.review(id);
      expect(repo.state.operations.single['server']['amount'], 200);
      await repo.resolve(id, useLocal: true);
      expect(requests.last['expected_version'], 'new');
      expect(requests.last['operation_id'], isNot(id));
      expect(repo.state.operations, isEmpty);
    },
  );

  test(
    'linked conflicts cannot be overwritten; rejected changes can be discarded',
    () async {
      final api = Api(
        client: MockClient((req) async {
          if (req.url.path == '/auth/me') return response(account);
          if (req.method == 'GET') {
            return response({
              ...draft,
              'id': 'entry',
              'version': 'new',
              'wishlist_purchase_id': 'purchase',
            });
          }
          return response({
            'error': {'message': 'Linked expense'},
          }, 409);
        }),
      );
      addTearDown(api.client.close);
      final repo = OfflineRepository(api, MemoryPersistence());
      await repo.open(account);
      await repo.enqueue('delete', id: 'entry', version: 'old');
      final id = repo.state.operations.single['request']['operation_id'];
      await repo.review(id);
      await expectLater(
        repo.resolve(id, useLocal: true),
        throwsA(isA<ApiException>()),
      );
      await repo.resolve(id, useLocal: false);
      expect(repo.state.operations, isEmpty);
    },
  );

  test('queue persistence failure never sends a transaction', () async {
    var calls = 0;
    final api = Api(
      client: MockClient((req) async {
        calls++;
        return response(account);
      }),
    );
    addTearDown(api.client.close);
    final disk = MemoryPersistence();
    final repo = OfflineRepository(api, disk);
    await repo.open(account);
    disk.fail = true;
    await expectLater(
      repo.enqueue('create', transaction: draft),
      throwsStateError,
    );
    expect(calls, 0);
    expect(repo.state.operations, isEmpty);
  });

  test('late cache reads after sign out cannot restore device data', () async {
    final gate = Completer<http.Response>();
    final api = Api(client: MockClient((req) => gate.future));
    addTearDown(api.client.close);
    final disk = MemoryPersistence();
    final repo = OfflineRepository(api, disk);
    await repo.open(account);
    final read = repo.read('/categories');
    final rejected = expectLater(read, throwsA(isA<ApiException>()));
    await repo.clear();
    gate.complete(response({'items': []}));
    await rejected;
    expect(disk.value, isNull);
  });
}
