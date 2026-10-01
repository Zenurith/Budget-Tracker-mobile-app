import 'package:flutter/material.dart';
import '../core/view/presenter_builder.dart';
import '../features/funding/presenter/funding_presenter.dart';
import '../features/planning/model/input_rules.dart';
import '../models/finance.dart';

class FundingScreen extends StatefulWidget {
  final FundingPresenter presenter;
  const FundingScreen({super.key, required this.presenter});
  @override
  State<FundingScreen> createState() => _FundingScreenState();
}

class _FundingScreenState extends State<FundingScreen> {
  FundingPresenter get p => widget.presenter;
  @override
  void initState() {
    super.initState();
    p.reload();
  }

  Future<void> editor(String mode, {Json? goal}) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => FundingEditor(presenter: p, mode: mode, goal: goal),
  );
  Future<void> remove(Json goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${goal['name']}?'),
        content: const Text(
          'This removes the goal and its future saving requirement. Reserved cash must be explicitly released or moved first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete goal'),
          ),
        ],
      ),
    );
    if (confirmed == true) await p.deleteGoal(goal['id'] as String);
  }

  @override
  Widget build(BuildContext context) => PresenterBuilder(
    presenter: p,
    builder: (context, state) {
      final data = state.data;
      final currency = data['currency'] as String? ?? '';
      String amount(String key) => data[key] == null
          ? 'Needs confirmation'
          : money(data[key] as int, currency);
      final goals = (data['goals'] as List? ?? []).cast<Json>();
      final names = {for (final goal in goals) goal['id']: goal['name']};
      return Scaffold(
        appBar: AppBar(
          title: const Text('Protected funding'),
          actions: [
            IconButton(
              tooltip: 'Refresh funding',
              onPressed: state.saving ? null : p.reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Protect essentials and savings using money you already have. Reservations earmark cash; they do not move money or create expenses.',
            ),
            if (state.busy || state.saving)
              const LinearProgressIndicator(semanticsLabel: 'Loading funding'),
            if (state.stale)
              const Text(
                'Activity changed or the connection failed. Refresh before making changes.',
              ),
            if (state.error != null)
              Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (state.error != null || state.stale)
              TextButton(
                onPressed: state.saving ? null : p.reload,
                child: const Text('Retry / refresh'),
              ),
            if (data.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['usable'] == true
                            ? 'Cash and plan reviewed'
                            : 'Needs updated information',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'Horizon: ${data['as_of']} through ${data['horizon_end']} (inclusive)',
                      ),
                      const Text(
                        'Without a confirmed income date, the horizon is 30 days. Expected income adds no available cash.',
                      ),
                      for (final reason in [
                        ...(data['missing_inputs'] as List? ?? []),
                        ...(data['stale_reasons'] as List? ?? []),
                      ])
                        Text('• $reason'),
                      const SizedBox(height: 12),
                      Text('Confirmed liquid cash: ${amount('liquid_total')}'),
                      Text(
                        'Unpaid obligations and essentials: ${amount('obligations_total')}',
                      ),
                      Text(
                        'Emergency reserve: ${amount('emergency_reserved')}',
                      ),
                      Text(
                        'Other savings reserved: ${amount('savings_reserved')}',
                      ),
                      Text('Additional buffer: ${amount('buffer_amount')}'),
                      const Divider(),
                      Text(
                        'Unallocated cash: ${amount('free_to_allocate')}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Coverage shortfall: ${amount('coverage_shortfall')}',
                      ),
                      if (data['usable'] != true)
                        const Text(
                          'Displayed totals are for review; contributions remain unavailable until inputs are complete and fresh.',
                        ),
                      if (data['has_overdue_obligations'] == true)
                        const Text(
                          'Overdue obligations need payment resolution before future wishlist readiness.',
                        ),
                      if (data['has_unfunded_required_savings'] == true)
                        const Text(
                          'Required saving contributions are protected as obligations until funded.',
                        ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: state.editable
                                ? () => editor('snapshot')
                                : null,
                            child: const Text('Reconcile cash'),
                          ),
                          OutlinedButton(
                            onPressed: state.editable
                                ? () => editor('plan')
                                : null,
                            child: const Text('Review funding plan'),
                          ),
                        ],
                      ),
                      if (data['snapshot'] != null)
                        Text('Cash as of ${data['snapshot']['as_of']}'),
                    ],
                  ),
                ),
              ),
              ExpansionTile(
                title: const Text('Obligations and allowance arithmetic'),
                children: [
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'All scheduled debts and recurring bills are protected, including overdue amounts and planned extra payments. Linked payments reduce the unpaid amount.',
                    ),
                  ),
                  for (final due in data['occurrences'] as List? ?? [])
                    ListTile(
                      title: Text('${due['name']} · ${due['due_date']}'),
                      subtitle: Text(
                        '${due['remaining_amount'] == null ? 'Missing payment amount' : money(due['remaining_amount'], currency)} unpaid${due['overdue'] == true ? ' · Overdue' : ''}',
                      ),
                    ),
                  for (final allowance in data['allowances'] as List? ?? [])
                    ListTile(
                      title: Text(allowance['name']),
                      subtitle: Text(
                        'Remaining total ${money(allowance['amount'], currency)}; linked obligations ${money(allowance['scheduled_within_allowance'], currency)}; additional protection ${money(allowance['additional_amount'], currency)}',
                      ),
                    ),
                  ListTile(
                    title: const Text('Unfunded required savings'),
                    subtitle: Text(amount('required_savings')),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Protected savings goals',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Goals in included accounts reserve cash. Savings outside those accounts are shown separately and are never deducted again.',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: state.editable ? () => editor('goal') : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Add savings goal'),
                ),
              ),
              if (goals.isEmpty)
                const Text(
                  'No savings goals declared. Confirm this when reviewing your funding plan.',
                ),
              for (final goal in goals)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal['name'],
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${goal['kind'] == 'emergency' ? 'Emergency reserve' : 'Savings goal'} · target ${money(goal['target_amount'], currency)}',
                        ),
                        Text(
                          goal['included_in_cash'] == true
                              ? 'Reserved ${money(goal['funded_amount'], currency)} inside liquid cash'
                              : 'Outside liquid cash: ${money(goal['excluded_balance'], currency)}',
                        ),
                        if (goal['required_by'] != null)
                          Text(
                            'Required reserve ${money(goal['required_amount'], currency)} by ${goal['required_by']}; unfunded within horizon ${money(goal['required_unfunded'], currency)}',
                          ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton(
                              onPressed: state.editable
                                  ? () => editor('goal', goal: goal)
                                  : null,
                              child: const Text('Edit goal'),
                            ),
                            if (goal['included_in_cash'] == true) ...[
                              FilledButton.tonal(
                                onPressed:
                                    state.editable &&
                                        data['can_allocate'] == true
                                    ? () => editor('allocate', goal: goal)
                                    : null,
                                child: const Text('Reserve cash'),
                              ),
                              TextButton(
                                onPressed:
                                    state.editable && goal['funded_amount'] > 0
                                    ? () => editor('release', goal: goal)
                                    : null,
                                child: const Text('Release cash'),
                              ),
                              TextButton(
                                onPressed:
                                    state.editable &&
                                        data['usable'] == true &&
                                        goal['funded_amount'] > 0
                                    ? () => editor('reallocate', goal: goal)
                                    : null,
                                child: const Text('Move reservation'),
                              ),
                            ],
                            TextButton(
                              onPressed: state.editable
                                  ? () => remove(goal)
                                  : null,
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Future monthly surplus: ${amount('monthly_forecast_surplus')}',
                      ),
                      const Text(
                        'This is a forward-looking plan after essentials, debt and protected savings. It is not included in unallocated cash.',
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                'Reservation history',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (state.events.isEmpty)
                const Text('No reservation changes yet.'),
              for (final event in state.events)
                ListTile(
                  title: Text(
                    '${event['kind']} · ${money(event['amount'], currency)}',
                  ),
                  subtitle: Text(
                    '${event['source_id'] == null ? 'Unallocated cash' : names[event['source_id']] ?? 'Former goal'} → ${event['target_id'] == null ? 'Unallocated cash' : names[event['target_id']] ?? 'Former goal'}\n${event['created_at']}',
                  ),
                ),
              if (state.events.length < state.total)
                TextButton(
                  onPressed: state.busy || state.saving ? null : p.loadEvents,
                  child: const Text('Load more history'),
                ),
              for (final warning in data['warnings'] as List? ?? [])
                Text(warning as String),
            ],
          ],
        ),
      );
    },
  );
}

class FundingEditor extends StatefulWidget {
  final FundingPresenter presenter;
  final String mode;
  final Json? goal;
  const FundingEditor({
    super.key,
    required this.presenter,
    required this.mode,
    this.goal,
  });
  @override
  State<FundingEditor> createState() => _FundingEditorState();
}

class _FundingEditorState extends State<FundingEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  final rows = <_FundingRow>[];
  bool busy = false, confirmed = false, included = true;
  String kind = 'savings';
  String? target, error;
  FundingPresenter get p => widget.presenter;
  Json get data => p.state.data;
  String get currency => data['currency'] as String;
  bool get moving =>
      ['allocate', 'release', 'reallocate'].contains(widget.mode);
  String get title => {
    'snapshot': 'Reconcile liquid cash',
    'plan': 'Review funding plan',
    'goal': 'Savings goal',
    'allocate': 'Reserve cash',
    'release': 'Release cash',
    'reallocate': 'Move reservation',
  }[widget.mode]!;
  @override
  void initState() {
    super.initState();
    final initial = widget.mode == 'snapshot'
        ? data['snapshot'] as Json? ?? {}
        : widget.mode == 'plan'
        ? data['plan'] as Json? ?? {}
        : widget.goal ?? {};
    for (final key in [
      'name',
      'target_amount',
      'excluded_balance',
      'required_amount',
      'required_by',
      'buffer_amount',
      'monthly_forecast_surplus',
      'next_income_date',
      'amount',
    ]) {
      final value = initial[key];
      fields[key] = TextEditingController(
        text: value == null
            ? ''
            : value is int
            ? (value / 100).toStringAsFixed(2)
            : value.toString(),
      );
    }
    fields['as_of'] = TextEditingController(
      text: DateTime.now().toUtc().toIso8601String(),
    );
    if (widget.mode == 'snapshot') {
      for (final a in initial['accounts'] as List? ?? []) {
        rows.add(_FundingRow(a));
      }
      if (rows.isEmpty) rows.add(_FundingRow({}));
    }
    if (widget.mode == 'plan') {
      for (final a in initial['essential_allowances'] as List? ?? []) {
        rows.add(_FundingRow(a));
      }
    }
    included = initial['included_in_cash'] as bool? ?? true;
    kind = initial['kind'] as String? ?? 'savings';
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    for (final row in [...rows, ...retired]) {
      row.dispose();
    }
    super.dispose();
  }

  Widget field(
    String key,
    String label, {
    bool monetary = false,
    bool optional = false,
    bool signed = false,
    bool date = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: fields[key],
      enabled: !busy,
      decoration: InputDecoration(labelText: label),
      keyboardType: monetary
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      validator: (v) {
        final value = (v ?? '').trim();
        if (optional && value.isEmpty) return null;
        if (date) return PlanningInputRules.date(value);
        if (monetary) {
          return PlanningInputRules.money(
            signed && value.startsWith('-') ? value.substring(1) : value,
          );
        }
        return value.isEmpty || value.length > 80
            ? 'Enter 1–80 characters'
            : null;
      },
    ),
  );
  int amount(String key) {
    final value = fields[key]!.text.trim();
    return (PlanningInputRules.amount(
              value.startsWith('-') ? value.substring(1) : value,
            ) ??
            0) *
        (value.startsWith('-') ? -1 : 1);
  }

  Widget rowsEditor(bool accounts) => Column(
    children: [
      for (var i = 0; i < rows.length; i++)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextFormField(
                  controller: rows[i].name,
                  enabled: !busy,
                  decoration: InputDecoration(
                    labelText: accounts ? 'Account name' : 'Allowance name',
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty || v!.trim().length > 80
                      ? 'Enter a name (up to 80 characters)'
                      : null,
                ),
                TextFormField(
                  controller: rows[i].amount,
                  enabled: !busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: accounts
                        ? 'Current balance ($currency)'
                        : 'Remaining total including linked bills ($currency)',
                  ),
                  validator: PlanningInputRules.money,
                ),
                if (!accounts) ...[
                  const Text(
                    'Select scheduled items already included in this allowance. The server subtracts their unpaid amounts from the additional allowance.',
                  ),
                  for (final schedule in data['schedules'] as List? ?? [])
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(schedule['name']),
                      value: rows[i].links.contains(schedule['id']),
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              if (v!) {
                                rows[i].links.add(schedule['id']);
                              } else {
                                rows[i].links.remove(schedule['id']);
                              }
                            }),
                    ),
                ],
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          final row = rows.removeAt(i);
                          retired.add(row);
                        }),
                  child: const Text('Remove row'),
                ),
              ],
            ),
          ),
        ),
      TextButton.icon(
        onPressed: busy
            ? null
            : () => setState(() => rows.add(_FundingRow({}))),
        icon: const Icon(Icons.add),
        label: Text(
          accounts ? 'Add included account' : 'Add essential allowance',
        ),
      ),
    ],
  );
  final retired = <_FundingRow>[];
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.mode == 'snapshot') ...[
                  const Text(
                    'Enter actual cash, debit and e-wallet balances now, after spending already made. Include earmarked reserves held in these accounts. Exclude credit limits, expected salary and savings in other accounts.',
                  ),
                  rowsEditor(true),
                  TextFormField(
                    controller: fields['as_of'],
                    enabled: !busy,
                    decoration: const InputDecoration(
                      labelText: 'Balance as-of time (ISO 8601 with timezone)',
                    ),
                    validator: (v) => DateTime.tryParse(v ?? '') == null
                        ? 'Enter a valid timestamp'
                        : null,
                  ),
                ],
                if (widget.mode == 'plan') ...[
                  Text(
                    'Review all unpaid occurrences in the funding screen, including overdue bills. Current displayed horizon ends ${data['horizon_end']}.',
                  ),
                  const SizedBox(height: 12),
                  field(
                    'next_income_date',
                    'Next confirmed income date · blank for 30 days',
                    optional: true,
                    date: true,
                  ),
                  field(
                    'buffer_amount',
                    'Additional cash buffer ($currency) · enter 0 if none',
                    monetary: true,
                  ),
                  field(
                    'monthly_forecast_surplus',
                    'Monthly future surplus ($currency) · enter 0 or a shortfall',
                    monetary: true,
                    signed: true,
                  ),
                  const Text(
                    'Allowances cover remaining essentials during this horizon. Do not enter an overall spending budget as another reserve.',
                  ),
                  rowsEditor(false),
                  const Text(
                    'No allowance rows explicitly means no additional essentials beyond the scheduled items. Review emergency and other savings goals before confirming.',
                  ),
                ],
                if (widget.mode == 'goal') ...[
                  field('name', 'Goal name'),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: 'Goal type'),
                    items: const [
                      DropdownMenuItem(
                        value: 'savings',
                        child: Text('Protected savings'),
                      ),
                      DropdownMenuItem(
                        value: 'emergency',
                        child: Text('Emergency reserve'),
                      ),
                    ],
                    onChanged: busy ? null : (v) => setState(() => kind = v!),
                  ),
                  const SizedBox(height: 14),
                  field(
                    'target_amount',
                    'Target amount ($currency)',
                    monetary: true,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Held inside included cash accounts'),
                    value: included,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => included = v),
                  ),
                  if (included) ...[
                    const Text(
                      'Create the goal, review the funding plan, then explicitly reserve cash. Targets alone are not funded money.',
                    ),
                    field(
                      'required_amount',
                      'Required funded reserve · optional',
                      monetary: true,
                      optional: true,
                    ),
                    field(
                      'required_by',
                      'Required by (YYYY-MM-DD) · optional',
                      date: true,
                      optional: true,
                    ),
                    const Text(
                      'An unfunded required reserve due within the horizon is protected as an obligation. Reserving it moves the amount into savings without counting it twice.',
                    ),
                  ] else ...[
                    field(
                      'excluded_balance',
                      'Balance outside included cash ($currency)',
                      monetary: true,
                    ),
                    const Text(
                      'This balance is recorded for context. It is not added to liquid cash or subtracted as a cash reserve.',
                    ),
                  ],
                ],
                if (moving) ...[
                  Text(
                    '${widget.goal!['name']} · reserved ${money(widget.goal!['funded_amount'], currency)}',
                  ),
                  field('amount', 'Amount ($currency)', monetary: true),
                  if (widget.mode == 'reallocate')
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Destination goal',
                      ),
                      items: [
                        for (final goal in data['goals'] as List)
                          if (goal['included_in_cash'] == true &&
                              goal['id'] != widget.goal!['id'])
                            DropdownMenuItem(
                              value: goal['id'] as String,
                              child: Text(goal['name'] as String),
                            ),
                      ],
                      validator: (v) =>
                          v == null ? 'Select a destination' : null,
                      onChanged: busy ? null : (v) => target = v,
                    ),
                  const Text(
                    'This changes reservations only. It does not transfer money between bank accounts or record an expense. Required savings and other obligations remain protected.',
                  ),
                ],
                if (widget.mode != 'goal')
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: confirmed,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => confirmed = v!),
                    title: Text(
                      widget.mode == 'snapshot'
                          ? 'I reconciled these balances, including outside spending and all reserves in these accounts'
                          : widget.mode == 'plan'
                          ? 'I reviewed this horizon, all obligations, allowances and savings requirements, including any zero or none values'
                          : 'I confirm this reservation change',
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
          onPressed: busy || (widget.mode != 'goal' && !confirmed)
              ? null
              : save,
          child: Text(
            busy
                ? 'Saving…'
                : widget.mode == 'goal'
                ? 'Save goal'
                : 'Confirm',
          ),
        ),
      ],
    ),
  );
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (widget.mode == 'snapshot' && rows.isEmpty) {
      setState(
        () => error = 'Enter at least one account, using zero if needed.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    bool ok;
    if (widget.mode == 'snapshot') {
      ok = await p.saveSnapshot({
        'accounts': [for (final row in rows) row.json(false)],
        'as_of': fields['as_of']!.text.trim(),
        'confirmed': true,
      });
    } else if (widget.mode == 'plan') {
      ok = await p.savePlan({
        'next_income_date': fields['next_income_date']!.text.trim().isEmpty
            ? null
            : fields['next_income_date']!.text.trim(),
        'buffer_amount': amount('buffer_amount'),
        'monthly_forecast_surplus': amount('monthly_forecast_surplus'),
        'essential_allowances': [for (final row in rows) row.json(true)],
        'confirmed': true,
      });
    } else if (widget.mode == 'goal') {
      ok = await p.saveGoal({
        'name': fields['name']!.text.trim(),
        'kind': kind,
        'target_amount': amount('target_amount'),
        'included_in_cash': included,
        'excluded_balance': included ? 0 : amount('excluded_balance'),
        'required_amount': included ? amount('required_amount') : 0,
        'required_by': included && fields['required_by']!.text.trim().isNotEmpty
            ? fields['required_by']!.text.trim()
            : null,
      }, id: widget.goal?['id']);
    } else {
      ok = await p.move(
        {
          'allocate': 'allocations',
          'release': 'releases',
          'reallocate': 'reallocations',
        }[widget.mode]!,
        {
          'amount': amount('amount'),
          if (widget.mode != 'allocate') 'source_id': widget.goal!['id'],
          if (widget.mode != 'release')
            'target_id': widget.mode == 'allocate'
                ? widget.goal!['id']
                : target,
        },
      );
    }
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        busy = false;
        error = p.state.error ?? 'Refresh and try again.';
      });
    }
  }
}

class _FundingRow {
  final TextEditingController name, amount;
  final Set<String> links;
  _FundingRow(Json data)
    : name = TextEditingController(text: data['name'] as String? ?? ''),
      amount = TextEditingController(
        text: data['amount'] == null
            ? ''
            : ((data['amount'] as int) / 100).toStringAsFixed(2),
      ),
      links = Set<String>.from(data['schedule_ids'] as List? ?? []);
  Json json(bool allowance) => {
    'name': name.text.trim(),
    'amount': PlanningInputRules.amount(amount.text),
    if (allowance) 'schedule_ids': links.toList(),
  };
  void dispose() {
    name.dispose();
    amount.dispose();
  }
}
