import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketwise/features/funding/presenter/funding_presenter.dart';
import 'package:pocketwise/models/finance.dart';
import 'package:pocketwise/views/wishlist_chat_screen.dart';
import 'support/fake_repositories.dart';

void main() {
  testWidgets(
    'follow-ups send bounded history and new conversation clears it',
    (tester) async {
      final requests = <Json>[];
      final p = FundingPresenter(
        FakeFundingRepository(),
        chatRequest: (request) async {
          requests.add(request);
          return {'reply': 'Reply to ${request['message']}'};
        },
      );
      p.setAccount(testAccount);
      await tester.pumpWidget(
        MaterialApp(home: WishlistChatScreen(presenter: p)),
      );
      for (var i = 0; i < 5; i++) {
        await tester.ensureVisible(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'Question $i');
        await tester.ensureVisible(find.text('Send to Gemini'));
        await tester.tap(find.text('Send to Gemini'));
        await tester.pumpAndSettle();
      }
      expect(requests.first['history'], isEmpty);
      expect((requests[1]['history'] as List).first['text'], 'Question 0');
      expect((requests.last['history'] as List).length, 6);
      expect((requests.last['history'] as List).first['text'], 'Question 1');
      await tester.tap(find.byTooltip('New conversation'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Fresh start');
      await tester.ensureVisible(find.text('Send to Gemini'));
      await tester.tap(find.text('Send to Gemini'));
      await tester.pumpAndSettle();
      expect(requests.last['history'], isEmpty);
      await tester.pumpWidget(const SizedBox());
      p.dispose();
    },
  );
  test('logout rejects in-flight Gemini reply', () async {
    final pending = Completer<Json>();
    final p = FundingPresenter(
      FakeFundingRepository(),
      chatRequest: (_) => pending.future,
    );
    p.setAccount(testAccount);
    final result = p.askGemini('Phone?');
    final expectation = expectLater(result, throwsStateError);
    p.setAccount(null);
    pending.complete({'reply': 'Old reply'});
    await expectation;
    p.dispose();
  });
  testWidgets(
    'chat sends explicit question and clears reply on account change',
    (tester) async {
      final p = FundingPresenter(
        FakeFundingRepository(),
        chatRequest: (question) async => {
          'reply': 'Review your cash first.',
          'draft': {'name': 'Phone', 'target_cost': 300000, 'currency': 'MYR'},
          'affordability': {
            'currency': 'MYR',
            'readiness': 'Still saving',
            'reasons': [],
            'available_to_reserve': 100000,
            'funding_gap': 200000,
          },
        },
      );
      p.setAccount(testAccount);
      await p.reload();
      await tester.pumpWidget(
        MaterialApp(home: WishlistChatScreen(presenter: p)),
      );
      await tester.enterText(find.byType(TextField), 'Can I plan for a phone?');
      await tester.tap(find.text('Send to Gemini'));
      await tester.pumpAndSettle();
      expect(find.text('Gemini: Review your cash first.'), findsOneWidget);
      expect(find.text('Review wish draft'), findsOneWidget);
      await tester.ensureVisible(find.text('Review wish draft'));
      await tester.tap(find.text('Review wish draft'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Phone'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '3000.00'), findsOneWidget);
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pumpAndSettle();
      p.setAccount(null);
      await tester.pump();
      expect(find.text('Gemini: Review your cash first.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      p.dispose();
    },
  );
}
