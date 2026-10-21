import 'account_reconciliation_panel.dart';
import 'package:flutter/material.dart';
import '../core/view/presenter_builder.dart';
import '../features/accounts/presenter/account_presenter.dart';
import '../features/planning/model/input_rules.dart';
import '../models/finance.dart';

class AccountsScreen extends StatefulWidget {
  final AccountPresenter presenter;
  final String currency;
  const AccountsScreen({
    super.key,
    required this.presenter,
    required this.currency,
  });
  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  @override
  void initState() {
    super.initState();
    widget.presenter.reload();
  }

  Future<void> edit(String action, {String? account}) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AccountEditor(
      presenter: widget.presenter,
      currency: widget.currency,
      action: action,
      account: account,
    ),
  );
  @override
  Widget build(BuildContext context) => PresenterBuilder(
    presenter: widget.presenter,
    builder: (context, state) {
      final accounts = (state.data['items'] as List? ?? []).cast<Json>();
      String name(String id) =>
          accounts.where((a) => a['id'] == id).firstOrNull?['name']
              as String? ??
          'Account';
      return Scaffold(
        appBar: AppBar(
          title: const Text('Accounts & transfers'),
          actions: [
            IconButton(
              onPressed: state.busy ? null : widget.presenter.reload,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh accounts',
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (state.busy) const LinearProgressIndicator(),
            if (state.error != null)
              Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const Text(
              'Account balances use their opening amounts, assigned transactions and transfers through today. They do not automatically change your existing budget-wide opening balances or Protected Funding cash.',
            ),
            const SizedBox(height: 12),
            Text(
              '${state.data['unassigned_count'] ?? '—'} transactions are unassigned. Edit existing transactions to choose an account; CSV imports and linked payments remain unassigned until corrected through their existing flows.',
            ),
            Wrap(
              spacing: 12,
              children: [
                FilledButton(
                  onPressed: state.busy ? null : () => edit('account'),
                  child: const Text('Add account'),
                ),
                OutlinedButton(
                  onPressed:
                      state.busy ||
                          accounts.where((a) => a['archived'] != true).length <
                              2
                      ? null
                      : () => edit('transfer'),
                  child: const Text('Record transfer'),
                ),
              ],
            ),
            for (final account in accounts)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${account['name']}${account['archived'] == true ? ' · Archived' : ''}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'Recorded balance: ${money(account['balance'], widget.currency)}',
                      ),
                      Text(
                        'Opening ${money(account['opening_amount'], widget.currency)} on ${account['opening_date']}',
                      ),
                      TextButton(
                        onPressed: state.busy
                            ? null
                            : () => edit('update', account: account['id']),
                        child: const Text('Edit / archive account'),
                      ),
                      TextButton(
                        onPressed: state.busy || account['archived'] == true
                            ? null
                            : () => edit('reconcile', account: account['id']),
                        child: const Text('Check actual balance'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Balance checks',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Checks preserve the comparison at that time. They do not create adjustments or update funding cash.',
            ),
            for (final check in state.data['checks'] as List? ?? [])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${name(check['account_id'])} · ${check['as_of']}'),
                subtitle: Text(
                  'Actual ${money(check['actual'], widget.currency)} · Recorded ${money(check['recorded'], widget.currency)}\nDifference ${money(check['difference'], widget.currency)}',
                ),
              ),
            Text(
              'Account changes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Opening corrections change recorded balances, not real money. Past balance checks keep their original values.',
            ),
            for (final change in state.data['changes'] as List? ?? [])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${change['before']['name']} → ${change['after']['name']}',
                ),
                subtitle: Text(
                  '${change['created_at']}\nOpening ${money(change['before']['opening_amount'], widget.currency)} on ${change['before']['opening_date']} → ${money(change['after']['opening_amount'], widget.currency)} on ${change['after']['opening_date']}\n${change['after']['archived'] == true ? 'Archived' : 'Active'}',
                ),
              ),
            Text('Transfers', style: Theme.of(context).textTheme.titleLarge),
            const Text(
              'Transfers move recorded money between accounts without changing income, spending or budgets. To correct a transfer, record the opposite transfer, then the correct one.',
            ),
            for (final transfer in state.data['transfers'] as List? ?? [])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${name(transfer['from_account'])} → ${name(transfer['to_account'])}',
                ),
                subtitle: Text(
                  '${transfer['date']} · ${money(transfer['amount'], widget.currency)}\n${transfer['note']}',
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _AccountEditor extends StatefulWidget {
  final AccountPresenter presenter;
  final String currency, action;
  final String? account;
  const _AccountEditor({
    required this.presenter,
    required this.currency,
    required this.action,
    this.account,
  });
  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<_AccountEditor> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      amount = TextEditingController(),
      note = TextEditingController();
  late final date = TextEditingController(
    text:
        widget.presenter.state.data['as_of'] as String? ??
        dateOf(DateTime.now()),
  );
  String? from, to;
  bool confirmed = false, archived = false;
  Json initial = const {};
  @override
  void initState() {
    super.initState();
    if (widget.action == 'update') {
      initial = (widget.presenter.state.data['items'] as List)
          .cast<Json>()
          .firstWhere((a) => a['id'] == widget.account);
      name.text = initial['name'];
      amount.text = ((initial['opening_amount'] as int) / 100).toStringAsFixed(
        2,
      );
      date.text = initial['opening_date'];
      archived = initial['archived'] == true;
    }
  }

  int? parsed() {
    final text = amount.text.trim();
    final value = PlanningInputRules.amount(
      text.startsWith('-') ? text.substring(1) : text,
    );
    return value == null
        ? null
        : text.startsWith('-')
        ? -value
        : value;
  }

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    note.dispose();
    date.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PresenterBuilder(
    presenter: widget.presenter,
    builder: (context, state) {
      final transfer = widget.action == 'transfer',
          creating = widget.action == 'account' || widget.action == 'update';
      final accounts = (state.data['items'] as List? ?? [])
          .cast<Json>()
          .where((a) => a['archived'] != true)
          .toList();
      return PopScope(
        canPop: !state.busy,
        child: AlertDialog(
          scrollable: true,
          title: Text(
            creating
                ? (widget.action == 'update' ? 'Edit account' : 'Add account')
                : transfer
                ? 'Record transfer'
                : 'Check actual balance',
          ),
          content: SizedBox(
            width: 440,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (creating) ...[
                    const Text(
                      'Use the balance at the start of your opening date. Assign only transactions on or after that date. Opening amounts are separate from existing budget-wide opening balances; do not count them as income.',
                    ),
                    TextFormField(
                      controller: name,
                      enabled: !state.busy,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        labelText: 'Account name',
                      ),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Enter a name' : null,
                    ),
                  ],
                  if (transfer) ...[
                    for (final source in [true, false])
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: source ? 'From account' : 'To account',
                        ),
                        items: [
                          for (final a in accounts)
                            DropdownMenuItem(
                              value: a['id'] as String,
                              child: Text(a['name']),
                            ),
                        ],
                        onChanged: state.busy
                            ? null
                            : (v) => setState(() {
                                if (source) {
                                  from = v;
                                } else {
                                  to = v;
                                }
                              }),
                        validator: (v) => v == null
                            ? 'Choose an account'
                            : !source && v == from
                            ? 'Choose a different account'
                            : null,
                      ),
                  ],
                  if (!creating && !transfer)
                    if (accounts
                            .where((a) => a['id'] == widget.account)
                            .firstOrNull
                        case final Json selected)
                      AccountReconciliationPanel(
                        account: selected,
                        data: state.data,
                        actual: parsed(),
                        currency: widget.currency,
                      ),
                  TextFormField(
                    onChanged: (_) => setState(() => confirmed = false),
                    controller: amount,
                    enabled: !state.busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          '${creating
                              ? 'Opening amount'
                              : transfer
                              ? 'Transfer amount'
                              : 'Actual balance'} (${widget.currency})',
                    ),
                    validator: (_) =>
                        parsed() == null ||
                            parsed()!.abs() > 100000000000 ||
                            transfer && parsed()! <= 0
                        ? (transfer
                              ? 'Enter a positive amount with up to 2 decimals'
                              : 'Enter an amount with up to 2 decimals')
                        : null,
                  ),
                  if (creating || transfer)
                    TextFormField(
                      controller: date,
                      enabled: !state.busy,
                      decoration: InputDecoration(
                        labelText: creating
                            ? 'Opening date (YYYY-MM-DD)'
                            : 'Transfer date (YYYY-MM-DD)',
                      ),
                      validator: (v) => PlanningInputRules.date(v),
                    ),
                  if (transfer)
                    TextFormField(
                      controller: note,
                      enabled: !state.busy,
                      maxLength: 500,
                      decoration: const InputDecoration(labelText: 'Note'),
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: confirmed,
                    onChanged: state.busy
                        ? null
                        : (v) => setState(() => confirmed = v ?? false),
                    title: Text(
                      transfer
                          ? 'This transfer already happened. Saving only records it.'
                          : 'I have reviewed these amounts and dates.',
                    ),
                  ),
                  if (widget.action == 'update') ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Archived'),
                      subtitle: const Text(
                        'Keep history, but prevent new assignments and transfers. Turn off to restore.',
                      ),
                      value: archived,
                      onChanged: state.busy
                          ? null
                          : (v) => setState(() => archived = v),
                    ),
                    const Text(
                      'Opening corrections change this account’s recorded balance. Existing transactions, transfers and past balance checks stay unchanged.',
                    ),
                  ],
                  if (state.error != null) Text(state.error!),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: state.busy ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: state.busy || !confirmed || state.data.isEmpty
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      final saved = await widget.presenter.save(
                        widget.action,
                        creating
                            ? {
                                'name': name.text.trim(),
                                'opening_amount': parsed(),
                                'opening_date': date.text,
                                if (widget.action == 'update') ...{
                                  'account_id': widget.account,
                                  'expected_revision': initial['revision'] ?? 0,
                                  'archived': archived,
                                },
                              }
                            : transfer
                            ? {
                                'from_account': from,
                                'to_account': to,
                                'amount': parsed(),
                                'date': date.text,
                                'note': note.text.trim(),
                              }
                            : {
                                'account_id': widget.account,
                                'actual': parsed(),
                              },
                      );
                      if (saved && context.mounted) Navigator.pop(context);
                    },
              child: Text(state.busy ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      );
    },
  );
}
