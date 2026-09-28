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
  test('money input preserves exact minor units and rejects invalid values', () {
    expect(minorUnits('15.50'),1550); expect(minorUnits('0.01'),1); expect(minorUnits('12.3'),1230);
    for (final value in ['10.555','-10','0','hello']) { expect(minorUnits(value),isNull); }
  });
  testWidgets('auth screen delegates validation to its presenter', (tester) async {
    final repository = FakeRepositories();
    await tester.pumpWidget(PocketwiseApp(presenters:testPresenters(repository)));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton,'Sign in'));
    await tester.tap(find.widgetWithText(FilledButton,'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(repository.authCalls,0);
  });
  testWidgets('natural entry previews without saving and confirms exactly once', (tester) async {
    final repository = FakeRepositories()..account=testAccount;
    final presenters = testPresenters(repository);
    await presenters.initialize();
    await presenters.overview.reload();
    addTearDown(presenters.dispose);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(context)=>TextButton(onPressed:()=>showEntryEditor(context,presenters,natural:true),child:const Text('Open'))))));
    await tester.tap(find.text('Open')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first,'Spent 15.50 on lunch yesterday');
    await tester.tap(find.text('Find the details')); await tester.pumpAndSettle();
    expect(find.text('Looking right? Review and confirm below.'),findsOneWidget);
    expect(repository.saves,isEmpty);
    await tester.tap(find.text('Confirm & save')); await tester.pumpAndSettle();
    expect(repository.saves.single.amount,1550);
    expect(repository.saves.single.source,'nlp');
    expect(find.text('Open'),findsOneWidget);
  });
  test('API rotates refresh token and retries an expired request', () async {
    var calls=0;
    final client=MockClient((request) async {
      if(request.url.path=='/auth/refresh') { return http.Response('{"access_token":"new-access","refresh_token":"new-refresh"}',200); }
      calls++;
      return request.headers['Authorization']=='Bearer new-access' ? http.Response('{"items":[]}',200) : http.Response('{"error":{"message":"expired"}}',401);
    });
    final api=Api(client:client)..accessToken='old-access'..refreshToken='old-refresh';
    expect(await api.request('GET','/transactions'),{'items':[]});
    expect(calls,2); expect(api.refreshToken,'new-refresh');
  });
}
