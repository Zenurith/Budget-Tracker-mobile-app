import 'funding_screen.dart';
import 'financial_helper_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/presentation/app_presenters.dart';
import '../core/view/presenter_builder.dart';
import '../features/planning/model/input_rules.dart';
import '../features/planning/presenter/planning_presenter.dart';
import '../models/finance.dart';
import 'planning_editors.dart';

class PlanningScreen extends StatelessWidget {
  final AppPresenters presenters;
  const PlanningScreen({super.key, required this.presenters});
  PlanningPresenter get p => presenters.planning;
  String get currency => presenters.auth.state.account?.currency ?? '';
  void message(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> scheduleEditor(
    BuildContext context,
    String kind, [
    Json? schedule,
  ]) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PlanningRecordEditor(
      kind: kind,
      currency: currency,
      initial: schedule,
      categories: presenters.overview.categories,
      onSave: (draft) => p.saveSchedule(kind, draft, id: schedule?['id']),
      error: () => p.state.error,
    ),
  );

  Future<bool> confirm(
    BuildContext context,
    String title,
    String explanation,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(explanation),
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
      ) ??
      false;

  @override
  Widget build(BuildContext context) => PresenterBuilder(
    presenter: p,
    builder: (context, state) => Scaffold(
      appBar: AppBar(
        title: const Text('Financial plan'),
        actions: [
          IconButton(
            tooltip: 'Reload plan',
            onPressed: state.saving ? null : p.reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: p.reload,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (state.busy || state.saving)
              const LinearProgressIndicator(
                semanticsLabel: 'Loading financial plan',
              ),
            if (state.error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const Text(
                        'Displayed data may be out of date. Reload before making further changes.',
                      ),
                      TextButton(
                        onPressed: state.saving ? null : p.reload,
                        child: const Text('Retry / reload'),
                      ),
                    ],
                  ),
                ),
              ),
            if (state.data.isNotEmpty) ...[
              OutlinedButton.icon(
                onPressed: state.busy || state.saving
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              FundingScreen(presenter: presenters.funding),
                        ),
                      ),
                icon: const Icon(Icons.savings_outlined),
                label: const Text('Open protected funding'),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Income and debt profile',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        state.data['complete'] == true
                            ? 'Inputs reviewed and complete'
                            : 'Inputs are incomplete',
                      ),
                      for (final missing
                          in state.data['missing_inputs'] as List? ?? [])
                        Text('• $missing'),
                      if (state.data['review_due'] == true)
                        const Text(
                          'Your review is over 30 days old. Check your inputs again.',
                        ),
                      if (state.profile != null) ...[
                        Text('Timezone: ${state.profile!['timezone']}'),
                        Text(
                          'Last review: ${state.profile!['reviewed_at'] ?? 'Not confirmed'}',
                        ),
                        for (final source
                            in state.profile!['income_sources'] as List)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${source['name']} · ${source['frequency']}',
                                ),
                                Text(
                                  'Gross: ${source['gross'] == null ? 'Unknown' : money(source['gross'], currency)} · Net: ${source['net'] == null ? 'Unknown' : money(source['net'], currency)}',
                                ),
                                Text(
                                  'Basis: ${source['basis']} · from ${source['start_date']}${source['end_date'] == null ? '' : ' to ${source['end_date']}'}',
                                ),
                                if ((source['notes'] as String).isNotEmpty)
                                  Text(source['notes'] as String),
                              ],
                            ),
                          ),
                      ],
                      const SizedBox(height: 14),
                      FilledButton.tonal(
                        onPressed: state.busy || state.saving
                            ? null
                            : () => showDialog<void>(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => FinancialProfileEditor(
                                  presenter: p,
                                  currency: currency,
                                ),
                              ),
                        child: const Text('Review income & debt profile'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: state.busy || state.saving
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => FinancialHelperScreen(
                                    presenter: presenters.helper,
                                  ),
                                ),
                              ),
                        icon: const Icon(Icons.calculate_outlined),
                        label: const Text('Open financial helper'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              schedules(context, state, 'debts', 'Debts'),
              schedules(context, state, 'commitments', 'Recurring bills'),
              const SizedBox(height: 16),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous obligation month',
                    onPressed: state.saving ? null : () => p.changeMonth(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      DateFormat('MMMM yyyy').format(state.month),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next obligation month',
                    onPressed: state.saving ? null : () => p.changeMonth(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Text(
                'Due dates · as of ${state.data['as_of']} (${state.data['timezone']})',
              ),
              const Text(
                'Debt schedules already appear here. Recurring bills should contain other obligations, not duplicate debt payments.',
              ),
              if (state.profile == null)
                const Text('Dates use UTC until you confirm your timezone.'),
              if (state.items('occurrences').isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No scheduled obligations in this month.'),
                ),
              for (final due in state.items('occurrences'))
                occurrenceCard(context, state, due),
            ],
          ],
        ),
      ),
    ),
  );

  Widget schedules(
    BuildContext context,
    PlanningState state,
    String kind,
    String title,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: state.busy || state.saving
                ? null
                : () => scheduleEditor(context, kind),
            icon: const Icon(Icons.add),
            label: Text(kind == 'debts' ? 'Add debt' : 'Add recurring bill'),
          ),
          if (state.items(kind).isEmpty)
            Text(
              kind == 'debts'
                  ? 'No debts listed. Confirm no debt explicitly in your profile if applicable.'
                  : 'No recurring bills listed.',
            ),
          for (final item in state.items(kind))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item['name'] as String),
              subtitle: Text(
                '${item['amount'] == null ? 'Payment unknown' : money(item['amount'], currency)} · ${item['frequency']} · ${item['status']}\nFrom ${item['start_date']}${item['end_date'] == null ? '' : ' to ${item['end_date']}'}',
              ),
              trailing: PopupMenuButton<String>(
                enabled: !state.busy && !state.saving,
                tooltip: '${item['name']} actions',
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit / close')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
                onSelected: (action) async {
                  if (action == 'edit') {
                    await scheduleEditor(context, kind, item);
                  } else if (await confirm(
                    context,
                    'Delete schedule?',
                    'Unpaid occurrences will be removed. Schedules with linked payments must be closed or explicitly unlinked first.',
                  )) {
                    final result = await p.deleteSchedule(kind, item['id']);
                    if (!result && context.mounted) {
                      message(
                        context,
                        p.state.error ?? 'Unable to delete schedule',
                      );
                    }
                  }
                },
              ),
            ),
        ],
      ),
    ),
  );

  Widget occurrenceCard(
    BuildContext context,
    PlanningState state,
    Json due,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${due['due_date']} · ${due['name']}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '${(due['state'] as String).replaceAll('_', ' ')}${due['overdue'] == true && due['state'] == 'partially_paid' ? ' · overdue' : ''}',
          ),
          Text(
            'Expected: ${due['expected_amount'] == null ? 'Unknown' : money(due['expected_amount'], currency)} · Paid: ${money(due['paid_amount'], currency)}',
          ),
          Text(
            'Unpaid: ${due['remaining_amount'] == null ? 'Unknown' : money(due['remaining_amount'], currency)}',
          ),
          if (due['remaining_amount'] != null &&
              (due['remaining_amount'] as int) > 0)
            OutlinedButton(
              onPressed: state.saving || state.busy
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => PaymentEditor(
                        presenter: p,
                        occurrence: due,
                        currency: currency,
                      ),
                    ),
              child: const Text('Record or link payment'),
            ),
          for (final link in due['payments'] as List)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${link['date']} · ${money(link['amount'], currency)}'),
                TextButton(
                  onPressed: state.saving || state.busy
                      ? null
                      : () async {
                          if (!await confirm(
                            context,
                            'Unlink this payment?',
                            'The expense stays in your transactions. This obligation becomes unpaid by the unlinked amount.',
                          )) {
                            return;
                          }
                          final result = await p.unlink(
                            due['id'],
                            link['transaction_id'],
                          );
                          if (!result && context.mounted) {
                            message(
                              context,
                              p.state.error ?? 'Unable to unlink payment',
                            );
                          }
                        },
                  child: const Text('Unlink'),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

class PaymentEditor extends StatefulWidget {
  final PlanningPresenter presenter;
  final Json occurrence;
  final String currency;
  const PaymentEditor({
    super.key,
    required this.presenter,
    required this.occurrence,
    required this.currency,
  });
  @override
  State<PaymentEditor> createState() => _PaymentEditorState();
}

class _PaymentEditorState extends State<PaymentEditor> {
  final form = GlobalKey<FormState>();
  late final amount = TextEditingController(
    text: ((widget.occurrence['remaining_amount'] as int) / 100)
        .toStringAsFixed(2),
  );
  late final date = TextEditingController(
    text:
        widget.presenter.state.data['as_of'] as String? ??
        dateOf(DateTime.now()),
  );
  String? existingId;
  late DateTime expenseMonth = DateTime.parse(
    widget.presenter.state.data['as_of'] as String? ?? dateOf(DateTime.now()),
  );
  List<Entry> candidates = [];
  bool loadingExpenses = false;
  int expenseRequest = 0;

  Future<void> loadExpenses([int offset = 0]) async {
    final request = ++expenseRequest;
    setState(() {
      expenseMonth = DateTime(expenseMonth.year, expenseMonth.month + offset);
      loadingExpenses = true;
      existingId = null;
      error = null;
      candidates = [];
    });
    try {
      final result = await widget.presenter.expenses(expenseMonth);
      if (mounted && request == expenseRequest) {
        setState(() {
          candidates = result;
          loadingExpenses = false;
        });
      }
    } catch (e) {
      if (mounted && request == expenseRequest) {
        setState(() {
          loadingExpenses = false;
          error = e.toString();
        });
      }
    }
  }

  String mode = 'new';
  bool busy = false, confirmed = false;
  String? error;
  @override
  void dispose() {
    amount.dispose();
    date.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text('Payment · ${widget.occurrence['name']}'),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: 'new',
                      child: Text('Record a new expense'),
                    ),
                    DropdownMenuItem(
                      value: 'existing',
                      child: Text('Link an existing expense'),
                    ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) {
                          setState(() => mode = v!);
                          if (mode == 'existing') loadExpenses();
                        },
                ),
                const SizedBox(height: 16),
                if (mode == 'new') ...[
                  TextFormField(
                    controller: amount,
                    enabled: !busy,
                    validator: (v) => PlanningInputRules.money(v),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount (${widget.currency})',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: date,
                    enabled: !busy,
                    validator: (v) => PlanningInputRules.date(v),
                    decoration: const InputDecoration(
                      labelText: 'Payment date (YYYY-MM-DD)',
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous expense month',
                        onPressed: busy || loadingExpenses
                            ? null
                            : () => loadExpenses(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          DateFormat('MMMM yyyy').format(expenseMonth),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next expense month',
                        onPressed: busy || loadingExpenses
                            ? null
                            : () => loadExpenses(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  if (loadingExpenses) const LinearProgressIndicator(),
                  if (!loadingExpenses && candidates.isEmpty)
                    const Text('No unlinked expenses in this month.'),
                  DropdownButtonFormField<String>(
                    key: ValueKey(expenseMonth),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Choose an existing expense',
                    ),
                    items: candidates
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.id,
                            child: Text(
                              '${dateOf(e.date)} · ${money(e.amount, widget.currency)} · ${e.note}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    validator: (v) => v == null ? 'Choose an expense' : null,
                    onChanged: busy || loadingExpenses
                        ? null
                        : (v) => existingId = v,
                  ),
                  TextButton(
                    onPressed: busy || loadingExpenses ? null : loadExpenses,
                    child: const Text('Refresh expenses'),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Linking uses the whole existing expense and creates no duplicate. To record a partial payment, enter only the amount already paid.',
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: confirmed,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => confirmed = v!),
                  title: const Text(
                    'I confirm this payment has already been made',
                  ),
                ),
                if (error != null)
                  Text(
                    error!,
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
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy || loadingExpenses || !confirmed
              ? null
              : () async {
                  if (!form.currentState!.validate()) return;
                  setState(() {
                    busy = true;
                    error = null;
                  });
                  final saved = await widget.presenter.pay(
                    widget.occurrence['id'],
                    mode == 'new'
                        ? {
                            'amount': PlanningInputRules.amount(amount.text),
                            'date': date.text,
                          }
                        : {'transaction_id': existingId!},
                  );
                  if (!context.mounted) return;
                  if (saved) {
                    Navigator.pop(context);
                  } else {
                    setState(() {
                      busy = false;
                      error = widget.presenter.state.error;
                    });
                  }
                },
          child: Text(busy ? 'Saving…' : 'Confirm payment'),
        ),
      ],
    ),
  );
}
