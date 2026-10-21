import 'package:flutter/material.dart';
import '../core/view/presenter_builder.dart';
import '../features/records/presenter/records_presenter.dart';
import '../models/finance.dart';

class RecordsScreen extends StatefulWidget {
  final RecordsPresenter presenter;
  final String currency;
  final int initialTab;
  final Future<void> Function()? reconcile;
  final Future<void> Function(DateTime start, DateTime end)? reviewTransactions;
  const RecordsScreen({
    super.key,
    required this.presenter,
    required this.currency,
    this.initialTab = 0,
    this.reconcile,
    this.reviewTransactions,
  });
  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  final selected = <int>{}, duplicates = <int>{};
  RecordsPresenter get p => widget.presenter;
  @override
  void initState() {
    super.initState();
    p.reload();
  }

  String amount(num value) => money(value, widget.currency);
  Future<bool> confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Widget pagination(Json data, {required bool balance}) {
    final page = data['page'] as int? ?? 1, total = data['total'] as int? ?? 0;
    return Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Page $page · $total records'),
        TextButton(
          onPressed: p.state.busy || page <= 1
              ? null
              : () => p.reload(
                  balancePage: balance ? page - 1 : 1,
                  historyPage: balance ? 1 : page - 1,
                ),
          child: const Text('Previous'),
        ),
        TextButton(
          onPressed: p.state.busy || page * 50 >= total
              ? null
              : () => p.reload(
                  balancePage: balance ? page + 1 : 1,
                  historyPage: balance ? 1 : page + 1,
                ),
          child: const Text('Next'),
        ),
      ],
    );
  }

  Widget balances(RecordsState state) {
    final opening = state.balances['opening'] as Json?;
    final recorded = state.balances['recorded'] as Json?;
    return ListView(
      key: const ValueKey('balance-records'),
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Opening balances are the amounts held at the start of your chosen date. They are not income. Recorded activity from that date changes your total balance.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Transactions currently share one budget-wide balance. Include the same named accounts when you reconcile cash; individual account movements are not tracked.',
        ),
        const SizedBox(height: 16),
        Text(
          opening == null
              ? 'No opening balance set'
              : 'Opening total: ${amount(opening['total'])} on ${opening['as_of']}',
        ),
        if (opening != null)
          for (final account in opening['accounts'] as List)
            Text('${account['name']}: ${amount(account['amount'])}'),
        if (recorded != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How your recorded balance adds up',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Opening balances: ${amount(recorded['opening_total'])}',
                  ),
                  Text(
                    'Net recorded activity: ${amount(recorded['movement'])}',
                  ),
                  Text(
                    'Recorded balance through ${recorded['as_of']}: ${amount(recorded['balance'])}',
                  ),
                  const Text(
                    'Net activity is recorded income minus expenses. This is not a verified bank balance.',
                  ),
                  if (widget.reviewTransactions != null && opening != null)
                    TextButton.icon(
                      onPressed: state.busy || state.error != null
                          ? null
                          : () => widget.reviewTransactions!(
                              DateTime.parse(opening['as_of']),
                              DateTime.parse(recorded['as_of']),
                            ),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Review balance transactions'),
                    ),
                ],
              ),
            ),
          ),
        ],
        Wrap(
          spacing: 12,
          children: [
            FilledButton(
              onPressed: state.busy
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => OpeningEditor(
                        presenter: p,
                        currency: widget.currency,
                      ),
                    ),
              child: const Text('Set opening balances'),
            ),
            if (widget.reconcile != null)
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () async {
                        await widget.reconcile!();
                        if (mounted) await p.reload();
                      },
                child: const Text('Reconcile cash'),
              ),
          ],
        ),
        const Divider(height: 32),
        Text(
          'Balance and reconciliation history',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Past checks preserve the values recorded at the time. Differences do not automatically create transactions.',
        ),
        if ((state.balances['items'] as List? ?? []).isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No balance history yet.'),
          ),
        for (final row in state.balances['items'] as List? ?? [])
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row['kind'] == 'opening'
                        ? 'Opening balances updated'
                        : 'Cash reconciled',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(row['created_at']),
                  if (row['kind'] == 'opening')
                    Text(
                      '${amount(row['after']['total'])} from ${row['after']['as_of']}',
                    )
                  else ...[
                    Text(
                      'Observed cash: ${amount(row['after']['liquid_total'])}',
                    ),
                    if (row['recorded'] != null) ...[
                      Text(
                        'Recorded at this check: ${amount(row['recorded']['balance'])}',
                      ),
                      ReconciliationDifference(
                        difference: row['difference'] as int,
                        currency: widget.currency,
                      ),
                    ] else
                      const Text(
                        'Comparison unavailable. Set opening balances for the same named accounts, then reconcile again.',
                      ),
                    Text(row['comparison_note'] ?? ''),
                    for (final a in row['after']['accounts'] as List)
                      Text('${a['name']}: ${amount(a['amount'])}'),
                  ],
                ],
              ),
            ),
          ),
        pagination(state.balances, balance: true),
      ],
    );
  }

  Widget csv(RecordsState state) => ListView(
    key: const ValueKey('csv-records'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Import transactions · ${widget.currency}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const Text(
        'Choose a UTF-8 CSV up to 1 MB / 1,000 rows. Use dates in YYYY-MM-DD format and positive amounts with up to two decimals. Category must match an existing category name or ID.',
      ),
      const SizedBox(height: 12),
      const SelectableText(
        'date,type,amount,category,note\n2026-10-01,expense,12.50,Food,Lunch',
      ),
      const Text(
        'Optional extra columns: payment_method,currency. If currency is omitted, your account currency applies. No conversion is performed.',
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: state.busy
            ? null
            : () async {
                final changed = await p.pickCSV();
                if (!mounted || !changed) return;
                setState(() {
                  selected.clear();
                  duplicates.clear();
                  for (final row in p.state.preview['items'] as List? ?? []) {
                    if (row['error'] == null && row['duplicate'] != true) {
                      selected.add(row['row'] as int);
                    }
                  }
                });
              },
        icon: const Icon(Icons.upload_file),
        label: const Text('Choose CSV file'),
      ),
      if (state.preview.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Possible duplicates match date, type, amount and note. They are deselected; select one only if it is a separate real transaction.',
          ),
        ),
        Text('${selected.length} of ${state.preview['total']} rows selected'),
        for (final row in state.preview['items'] as List)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: selected.contains(row['row']),
            title: Text(
              row['error'] != null
                  ? 'Row ${row['row']}: invalid'
                  : 'Row ${row['row']}: ${row['transaction']['date']} · ${row['transaction']['type']} · ${amount(row['transaction']['amount'])}',
            ),
            subtitle: Text(
              row['error'] ??
                  '${row['transaction']['note']}\n${row['duplicate_reason'] ?? 'No matching transaction found'}',
            ),
            onChanged: state.busy || row['error'] != null
                ? null
                : (value) async {
                    if (value == true &&
                        row['duplicate'] == true &&
                        !await confirm(
                          'Import possible duplicate?',
                          'This row may already be recorded. Include it only if it is a separate transaction.',
                          'Include duplicate',
                        )) {
                      return;
                    }
                    if (!mounted) return;
                    setState(() {
                      final id = row['row'] as int;
                      if (value == true) {
                        selected.add(id);
                        if (row['duplicate'] == true) duplicates.add(id);
                      } else {
                        selected.remove(id);
                        duplicates.remove(id);
                      }
                    });
                  },
          ),
        FilledButton(
          onPressed: state.busy || selected.isEmpty
              ? null
              : () async {
                  if (!await confirm(
                    'Import ${selected.length} transactions?',
                    'These entries will update your recorded totals and budgets. You can undo individual imported transactions in Change history.',
                    'Import',
                  )) {
                    return;
                  }
                  await p.importCSV(selected, duplicates);
                  if (mounted && p.state.preview.isEmpty) {
                    setState(() {
                      selected.clear();
                      duplicates.clear();
                    });
                  }
                },
          child: const Text('Import selected rows'),
        ),
      ],
    ],
  );
  String describe(Json? doc) => doc == null
      ? 'No transaction'
      : '${doc['date']} · ${doc['type']} · ${amount(doc['amount'])}\n${doc['note']} · ${doc['category_id']}';
  Widget history(RecordsState state) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Change history', style: Theme.of(context).textTheme.titleLarge),
      const Text(
        'Undo ordinary transaction additions, edits and deletions made in the last 30 days. Newer changes must be undone first. Linked purchases and bill payments keep their correction safeguards.',
      ),
      if ((state.history['items'] as List? ?? []).isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No recent transaction changes.'),
        ),
      for (final row in state.history['items'] as List? ?? [])
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${row['action']} · ${row['created_at']}'),
                if (row['before'] != null)
                  Text('Before: ${describe(row['before'] as Json)}'),
                if (row['after'] != null)
                  Text('After: ${describe(row['after'] as Json)}'),
                if (row['undone'] == true)
                  const Text('Undone')
                else
                  TextButton.icon(
                    onPressed: state.busy
                        ? null
                        : () async {
                            if (await confirm(
                              'Undo this ${row['action']}?',
                              'Your recorded totals will change and protected cash will need review. This does not move real money.',
                              'Undo',
                            )) {
                              await p.undo(row['id'] as String);
                            }
                          },
                    icon: const Icon(Icons.undo),
                    label: const Text('Undo change'),
                  ),
              ],
            ),
          ),
        ),
      pagination(state.history, balance: false),
    ],
  );
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    initialIndex: widget.initialTab,
    child: PresenterBuilder(
      presenter: p,
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          title: const Text('Balances & records'),
          actions: [
            IconButton(
              onPressed: state.busy ? null : p.reload,
              tooltip: 'Refresh records',
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Balances'),
              Tab(text: 'CSV import'),
              Tab(text: 'Change history'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (state.busy) const LinearProgressIndicator(),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (state.message != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(state.message!),
              ),
            Expanded(
              child: TabBarView(
                children: [balances(state), csv(state), history(state)],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class OpeningEditor extends StatefulWidget {
  final RecordsPresenter presenter;
  final String currency;
  const OpeningEditor({
    super.key,
    required this.presenter,
    required this.currency,
  });
  @override
  State<OpeningEditor> createState() => _OpeningEditorState();
}

class _OpeningEditorState extends State<OpeningEditor> {
  final form = GlobalKey<FormState>();
  final date = TextEditingController();
  final rows = <(TextEditingController, TextEditingController)>[];
  bool confirmed = false;
  @override
  void initState() {
    super.initState();
    final opening = widget.presenter.state.balances['opening'] as Json?;
    date.text = opening?['as_of'] ?? dateOf(DateTime.now());
    for (final a in opening?['accounts'] as List? ?? []) {
      rows.add((
        TextEditingController(text: a['name']),
        TextEditingController(
          text: ((a['amount'] as num) / 100).toStringAsFixed(2),
        ),
      ));
    }
    if (rows.isEmpty) {
      rows.add((TextEditingController(), TextEditingController()));
    }
  }

  @override
  void dispose() {
    date.dispose();
    for (final row in rows) {
      row.$1.dispose();
      row.$2.dispose();
    }
    super.dispose();
  }

  int? parse(String text) {
    final value = text.trim();
    if (RegExp(r'^-?0+(\.0{1,2})?$').hasMatch(value)) return 0;
    final n = minorUnits(value.startsWith('-') ? value.substring(1) : value);
    return n == null
        ? null
        : value.startsWith('-')
        ? -n
        : n;
  }

  @override
  Widget build(BuildContext context) => PresenterBuilder(
    presenter: widget.presenter,
    builder: (context, state) => AlertDialog(
      title: const Text('Opening balances'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Enter ${widget.currency} balances at the start of this date, before that day’s transactions. Zero and negative opening amounts are allowed. These values are not income or verified available cash.',
                ),
                TextFormField(
                  controller: date,
                  enabled: !state.busy,
                  decoration: const InputDecoration(
                    labelText: 'Opening date (YYYY-MM-DD)',
                  ),
                  validator: (s) {
                    final parsed = DateTime.tryParse(s ?? '');
                    return parsed == null || dateOf(parsed) != s
                        ? 'Enter a valid YYYY-MM-DD date'
                        : null;
                  },
                ),
                for (final (index, row) in rows.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: row.$1,
                          enabled: !state.busy,
                          maxLength: 80,
                          decoration: InputDecoration(
                            labelText: 'Account ${index + 1} name',
                          ),
                          validator: (s) => s == null || s.trim().isEmpty
                              ? 'Enter an account name'
                              : null,
                        ),
                        TextFormField(
                          controller: row.$2,
                          enabled: !state.busy,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Opening amount (${widget.currency})',
                          ),
                          validator: (s) => parse(s ?? '') == null
                              ? 'Enter an amount with up to two decimals'
                              : null,
                        ),
                        if (rows.length > 1)
                          TextButton(
                            onPressed: state.busy
                                ? null
                                : () => setState(() {
                                    final removed = rows.removeAt(index);
                                    removed.$1.dispose();
                                    removed.$2.dispose();
                                  }),
                            child: const Text('Remove account'),
                          ),
                      ],
                    ),
                  ),
                TextButton(
                  onPressed: state.busy || rows.length >= 30
                      ? null
                      : () => setState(
                          () => rows.add((
                            TextEditingController(),
                            TextEditingController(),
                          )),
                        ),
                  child: const Text('Add account'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: confirmed,
                  onChanged: state.busy
                      ? null
                      : (v) => setState(() => confirmed = v ?? false),
                  title: const Text(
                    'I reviewed the date and all opening amounts.',
                  ),
                ),
                if (state.error != null)
                  Text(
                    state.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: state.busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: state.busy || !confirmed
              ? null
              : () async {
                  if (!form.currentState!.validate()) return;
                  final ok = await widget.presenter.saveOpening({
                    'as_of': date.text,
                    'accounts': [
                      for (final row in rows)
                        {
                          'name': row.$1.text.trim(),
                          'amount': parse(row.$2.text),
                        },
                    ],
                    'confirmed': true,
                  });
                  if (ok && context.mounted) Navigator.pop(context);
                },
          child: Text(state.busy ? 'Saving…' : 'Save opening balances'),
        ),
      ],
    ),
  );
}

class ReconciliationDifference extends StatelessWidget {
  final int difference;
  final String currency;
  const ReconciliationDifference({
    super.key,
    required this.difference,
    required this.currency,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 8),
      Text(
        difference == 0
            ? 'Cash matched the recorded balance at this check'
            : 'Observed cash was ${money(difference.abs(), currency)} ${difference > 0 ? 'higher' : 'lower'} than recorded',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: difference == 0 ? null : Theme.of(context).colorScheme.error,
        ),
      ),
      if (difference != 0) ...[
        const SizedBox(height: 8),
        const Text('What to check'),
        Text(
          difference < 0
              ? 'Look for missing expenses, duplicate income or an opening balance that was too high.'
              : 'Look for missing income, duplicate expenses or an opening balance that was too low.',
        ),
        const Text(
          'Check that the same accounts are included and that same-day transactions had already happened when you checked cash.',
        ),
        const Text(
          'Correct any records you find, then reconcile again. This difference does not identify a specific transaction or move money.',
        ),
      ],
    ],
  );
}
