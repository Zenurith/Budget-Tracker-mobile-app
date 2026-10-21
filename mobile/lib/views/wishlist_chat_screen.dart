import 'dart:async';
import 'package:flutter/material.dart';
import '../models/finance.dart';
import 'wishlist_screen.dart';
import '../features/funding/presenter/funding_presenter.dart';

class WishlistChatScreen extends StatefulWidget {
  final FundingPresenter presenter;
  const WishlistChatScreen({super.key, required this.presenter});
  @override
  State<WishlistChatScreen> createState() => _WishlistChatScreenState();
}

class _WishlistChatScreenState extends State<WishlistChatScreen>
    with WidgetsBindingObserver {
  final input = TextEditingController();
  final messages = <String>[];
  final history = <Json>[];
  Json? suggestion;
  Timer? expiry;
  bool busy = false;
  int generation = 0;
  String? error;
  StreamSubscription<FundingState>? subscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    subscription = widget.presenter.states.listen((_) => clear());
  }

  void clear() {
    if (!mounted) return;
    setState(() {
      generation++;
      messages.clear();
      history.clear();
      suggestion = null;
      expiry?.cancel();
      input.clear();
      busy = false;
      error = null;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) clear();
  }

  Future<void> send() async {
    final question = input.text.trim();
    if (question.isEmpty || busy) return;
    final request = ++generation;
    setState(() {
      busy = true;
      error = null;
      suggestion = null;
      expiry?.cancel();
    });
    try {
      final reply = await widget.presenter.askGemini(
        question,
        history: List<Json>.of(history),
      );
      if (!mounted || request != generation) return;
      setState(() {
        messages.add('You: $question');
        messages.add('Gemini: ${reply['reply']}');
        history.add({'role': 'user', 'text': question});
        final answer = reply['reply'] as String;
        history.add({
          'role': 'assistant',
          'text': answer.length > 2000 ? answer.substring(0, 2000) : answer,
        });
        while (history.length > 6) {
          history.removeRange(0, 2);
        }
        while (messages.length > 6) {
          messages.removeRange(0, 2);
        }
        suggestion = reply;
        expiry = Timer(const Duration(minutes: 1), () {
          if (mounted) setState(() => suggestion = null);
        });
        input.clear();
      });
    } catch (e) {
      if (mounted && request == generation) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && request == generation) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    expiry?.cancel();
    subscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Ask Gemini'),
      actions: [
        IconButton(
          tooltip: 'New conversation',
          icon: const Icon(Icons.refresh),
          onPressed: clear,
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Sending shares your question, up to three recent exchanges, and a limited funding summary with Google Gemini. Avoid including sensitive personal details. Replies are AI-generated guidance, not verified purchase approval. Nothing is saved or purchased.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Start with “Can I plan for a RM3,000 phone?”, then ask “What if it costs RM2,500?” Each reply uses fresh funding data. Earlier replies may be outdated. Only the last three exchanges are kept; long replies are shortened when sent.',
        ),
        for (final message in messages)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SelectableText(message),
          ),
        if (suggestion?['draft'] != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AI wish draft — review details'),
                  Text(
                    '${suggestion!['draft']['name']} · ${money(suggestion!['draft']['target_cost'], suggestion!['draft']['currency'])}',
                  ),
                  if (suggestion!['affordability'] case final Map card) ...[
                    const Text('Calculated from your funding plan'),
                    Text('${card['readiness']}'),
                    if (card['available_to_reserve'] != null)
                      Text(
                        'Available to reserve: ${money(card['available_to_reserve'], card['currency'])}',
                      ),
                    if (card['funding_gap'] != null)
                      Text(
                        'Additional funding needed: ${money(card['funding_gap'], card['currency'])}',
                      ),
                    for (final reason in card['reasons'] as List)
                      Text('$reason'),
                    const Text(
                      'Nothing reserved yet. This is not purchase approval. Figures expire after one minute.',
                    ),
                  ],
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            final draft = Map<String, dynamic>.from(
                              suggestion!['draft'],
                            );
                            await showDialog<void>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => WishlistEditor(
                                presenter: widget.presenter,
                                mode: 'item',
                                item: draft,
                              ),
                            );
                            if (mounted) clear();
                          },
                    child: const Text('Review wish draft'),
                  ),
                ],
              ),
            ),
          ),
        ],
        TextField(
          controller: input,
          enabled: !busy,
          maxLength: 2000,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Your wishlist question',
          ),
        ),
        FilledButton(
          onPressed: busy ? null : send,
          child: Text(busy ? 'Asking Gemini…' : 'Send to Gemini'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const Text(
          'Use the wishlist’s Add item action to review and save a wish.',
        ),
      ],
    ),
  );
}
