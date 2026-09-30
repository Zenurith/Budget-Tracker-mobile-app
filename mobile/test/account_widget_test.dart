import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketwise/data/api_repositories.dart';
import 'package:pocketwise/main.dart';
import 'package:pocketwise/services/api.dart';
import 'support/fake_repositories.dart';
import 'account_presenter_test.dart' show MemoryDestination;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('Settings edits name, retries errors and exports JSON', (
    tester,
  ) async {
    final repo = FakeRepositories()..account = testAccount;
    final destination = MemoryDestination();
    await tester.pumpWidget(
      PocketwiseApp(
        presenters: testPresenters(repo, exportDestination: destination),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit profile'));
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Alex Tan');
    repo.failure = 'offline';
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    expect(find.textContaining('offline'), findsOneWidget);
    repo.failure = null;
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Alex Tan'), findsOneWidget);
    await tester.ensureVisible(find.text('Export my data'));
    await tester.tap(find.text('Export my data'));
    await tester.pumpAndSettle();
    expect(jsonDecode(destination.contents!)['account']['name'], 'Alex Tan');
    expect(find.text('Your data export is ready.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'account endpoints refresh expired access tokens and preserve request',
    () async {
      for (final export in [false, true]) {
        var refreshes = 0, calls = 0;
        final api =
            Api(
                client: MockClient((request) async {
                  if (request.url.path == '/auth/refresh') {
                    refreshes++;
                    return http.Response(
                      '{"access_token":"new","refresh_token":"rotated"}',
                      200,
                    );
                  }
                  calls++;
                  expect(
                    request.url.path,
                    export ? '/auth/me/export' : '/auth/me',
                  );
                  expect(request.method, export ? 'GET' : 'PUT');
                  if (!export) {
                    expect(jsonDecode(request.body), {'name': 'New name'});
                  }
                  if (request.headers['Authorization'] != 'Bearer new') {
                    return http.Response(
                      '{"error":{"message":"expired"}}',
                      401,
                    );
                  }
                  return http.Response(
                    export
                        ? '{"schema_version":1}'
                        : '{"id":"alex","name":"New name","email":"alex@example.com","currency":"MYR"}',
                    200,
                  );
                }),
              )
              ..accessToken = 'expired'
              ..refreshToken = 'original';
        final repository = ApiAuthRepository(api);
        if (export) {
          expect((await repository.exportData())['schema_version'], 1);
        } else {
          expect((await repository.updateProfile('New name')).name, 'New name');
        }
        expect(refreshes, 1);
        expect(calls, 2);
        api.client.close();
      }
    },
  );
}
