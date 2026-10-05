import 'package:flutter/material.dart';
import '../core/view/presenter_builder.dart';
import '../features/sync/presenter/sync_presenter.dart';
import '../models/finance.dart';

class SyncBanner extends StatelessWidget {
  final SyncPresenter presenter;
  final String currency;
  final VoidCallback? reauthenticate;
  const SyncBanner({
    super.key,
    required this.presenter,
    required this.currency,
    this.reauthenticate,
  });
  @override
  Widget build(BuildContext context) => PresenterBuilder(
    presenter: presenter,
    builder: (context, state) {
      if (!state.offline && state.operations.isEmpty && state.error == null) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              '${state.offline ? 'Offline or waiting to reconnect. ' : ''}${state.operations.length} changes waiting to sync. Totals exclude pending changes.',
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => SyncScreen(
                    presenter: presenter,
                    currency: currency,
                    reauthenticate: reauthenticate,
                  ),
                ),
              ),
              child: const Text('Review sync'),
            ),
          ],
        ),
      );
    },
  );
}

class SyncScreen extends StatelessWidget {
  final SyncPresenter presenter;
  final String currency;
  final VoidCallback? reauthenticate;
  const SyncScreen({
    super.key,
    required this.presenter,
    required this.currency,
    this.reauthenticate,
  });
  Widget details(String title, Json? entry) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      if (entry == null)
        const Text('No transaction remains on the server.')
      else ...[
        Text(
          '${entry['type']} · ${money(entry['amount'], currency)} · ${entry['date']}',
        ),
        Text('Category: ${entry['category_id']} · ${entry['payment_method']}'),
        SelectableText(entry['note'] as String? ?? ''),
      ],
    ],
  );
  Future<void> resolve(BuildContext context, String id, bool local) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(local ? 'Apply your change?' : 'Keep the server version?'),
        content: Text(
          local
              ? 'Apply your queued edit or deletion to the server version you just reviewed. If it changes again, you will be asked to review it again.'
              : 'Discard this rejected local change. Server records stay as they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (yes == true) await presenter.resolve(id, useLocal: local);
  }

  @override
  Widget build(BuildContext context) => PresenterBuilder(
    presenter: presenter,
    builder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Offline & sync')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Recent records are cached on this device. Pending transaction changes are saved separately and excluded from reports until synchronized. Funding and purchase confirmation require an online review after the queue is resolved.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: state.busy ? null : presenter.synchronize,
            icon: const Icon(Icons.sync),
            label: Text(state.busy ? 'Syncing…' : 'Sync now'),
          ),
          if (state.error != null) Text(state.error!),
          if (reauthenticate != null && (state.error != null || state.offline))
            TextButton(
              onPressed: state.busy
                  ? null
                  : () {
                      Navigator.pop(context);
                      reauthenticate!();
                    },
              child: const Text('Sign in again · keep pending changes'),
            ),
          if (state.operations.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No pending changes.'),
            ),
          for (final op in state.operations)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${op['request']['action']} · ${op['status'] == 'conflict' ? 'Needs review' : 'Waiting to sync'}',
                      ),
                      Text('Saved on this device: ${op['created_at']}'),
                      if (op['request']['transaction'] != null)
                        details(
                          'Your change',
                          Map<String, dynamic>.from(
                            op['request']['transaction'],
                          ),
                        )
                      else
                        const Text('Your change: delete this transaction.'),
                      if (op['request']['action'] == 'delete' &&
                          op['before'] != null)
                        details(
                          'Transaction to delete',
                          Map<String, dynamic>.from(op['before']),
                        ),
                      if (op['error'] != null) Text(op['error']),
                      if (op['reviewed'] == true)
                        details(
                          'Current server version',
                          op['server'] == null
                              ? null
                              : Map<String, dynamic>.from(op['server']),
                        ),
                      if (op['status'] == 'conflict')
                        Wrap(
                          spacing: 8,
                          children: [
                            if (op['request']['transaction_id'] != null)
                              TextButton(
                                onPressed: state.busy
                                    ? null
                                    : () => presenter.review(
                                        op['request']['operation_id'],
                                      ),
                                child: const Text('Review server version'),
                              ),
                            TextButton(
                              onPressed: state.busy
                                  ? null
                                  : () => resolve(
                                      context,
                                      op['request']['operation_id'],
                                      false,
                                    ),
                              child: const Text('Discard local change'),
                            ),
                            if (op['reviewed'] == true &&
                                op['server'] != null &&
                                op['server']['wishlist_purchase_id'] == null &&
                                op['server']['commitment_occurrence_id'] ==
                                    null)
                              TextButton(
                                onPressed: state.busy
                                    ? null
                                    : () => resolve(
                                        context,
                                        op['request']['operation_id'],
                                        true,
                                      ),
                                child: const Text('Use my change'),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
