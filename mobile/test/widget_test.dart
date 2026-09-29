import 'dart:convert';
import 'package:pocketwise/core/model/contracts.dart';
import 'package:pocketwise/data/api_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketwise/main.dart';
import 'package:pocketwise/models/finance.dart';
import 'package:pocketwise/services/api.dart';
import 'package:pocketwise/views/entry_editor.dart';
import 'support/fake_repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'money input preserves exact minor units and rejects invalid values',
    () {
      expect(minorUnits('15.50'), 1550);
      expect(minorUnits('0.01'), 1);
      expect(minorUnits('12.3'), 1230);
      for (final value in ['10.555', '-10', '0', 'hello']) {
        expect(minorUnits(value), isNull);
      }
    },
  );
  testWidgets('auth screen delegates validation to its presenter', (
    tester,
  ) async {
    final repository = FakeRepositories();
    await tester.pumpWidget(
      PocketwiseApp(presenters: testPresenters(repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(repository.authCalls, 0);
  });
  testWidgets('demo asks for currency and cancellation creates no account', (
    tester,
  ) async {
    final repository = FakeRepositories();
    await tester.pumpWidget(
      PocketwiseApp(presenters: testPresenters(repository)),
    );
    await tester.pumpAndSettle();
    final demo = find.text('Take a look around · Try the demo');
    await tester.ensureVisible(demo);
    await tester.tap(demo);
    await tester.pumpAndSettle();
    expect(find.text('Choose your demo currency'), findsOneWidget);
    expect(repository.authCalls, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.authCalls, 0);
    await tester.tap(demo);
    await tester.pumpAndSettle();
    await tester.tap(find.text('USD'));
    await tester.pumpAndSettle();
    expect(repository.authCalls, 1);
    expect(repository.lastAuthInput!.mode, 'demo');
    expect(repository.lastAuthInput!.currency, 'USD');
  });
  test(
    'auth adapter sends selected currency for demo and registration',
    () async {
      for (final mode in ['demo', 'register', 'login']) {
        final api = Api(
          client: MockClient((request) async {
            expect(request.url.path, '/auth/$mode');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            if (mode == 'login') {
              expect(body.containsKey('currency'), isFalse);
            } else {
              expect(body['currency'], 'GBP');
            }
            if (mode == 'demo') expect(body.keys, ['currency']);
            return http.Response(
              jsonEncode({
                'access_token': 'access',
                'refresh_token': 'refresh',
                'user': {
                  'id': 'alex',
                  'name': 'Alex',
                  'email': 'alex@example.com',
                  'currency': 'GBP',
                },
              }),
              200,
            );
          }),
        );
        final account = await ApiAuthRepository(api).authenticate(
          AuthInput(
            mode: mode,
            currency: 'GBP',
            name: 'Alex',
            email: 'alex@example.com',
            password: 'password1',
          ),
        );
        expect(account.currency, 'GBP');
        api.client.close();
      }
    },
  );
  testWidgets(
    'natural entry previews without saving and confirms exactly once',
    (tester) async {
      final repository = FakeRepositories()..account = testAccount;
      final presenters = testPresenters(repository);
      await presenters.initialize();
      await presenters.overview.reload();
      addTearDown(presenters.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showEntryEditor(context, presenters, natural: true),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'Spent 15.50 on lunch yesterday',
      );
      await tester.tap(find.text('Find the details'));
      await tester.pumpAndSettle();
      expect(
        find.text('Looking right? Review and confirm below.'),
        findsOneWidget,
      );
      expect(repository.saves, isEmpty);
      await tester.tap(find.text('Confirm & save'));
      await tester.pumpAndSettle();
      expect(repository.saves.single.amount, 1550);
      expect(repository.saves.single.source, 'nlp');
      expect(find.text('Open'), findsOneWidget);
    },
  );
  test('API rotates refresh token and retries an expired request', () async {
    var calls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/auth/refresh') {
        return http.Response(
          '{"access_token":"new-access","refresh_token":"new-refresh"}',
          200,
        );
      }
      calls++;
      return request.headers['Authorization'] == 'Bearer new-access'
          ? http.Response('{"items":[]}', 200)
          : http.Response('{"error":{"message":"expired"}}', 401);
    });
    final api = Api(client: client)
      ..accessToken = 'old-access'
      ..refreshToken = 'old-refresh';
    expect(await api.request('GET', '/transactions'), {'items': []});
    expect(calls, 2);
    expect(api.refreshToken, 'new-refresh');
  });
}
