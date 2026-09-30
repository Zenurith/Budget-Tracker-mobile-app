import 'package:flutter/material.dart';
import '../core/model/contracts.dart';
import '../features/planning/model/input_rules.dart';
import '../features/planning/presenter/planning_presenter.dart';
import '../models/finance.dart';

class PlanningRecordEditor extends StatefulWidget {
  final String kind, currency;
  final Json? initial;
  final List<FinanceCategory> categories;
  final Future<bool> Function(Json) onSave;
  final String? Function() error;
  const PlanningRecordEditor({
    super.key,
    required this.kind,
    required this.currency,
    this.initial,
    this.categories = const [],
    required this.onSave,
    required this.error,
  });
  @override
  State<PlanningRecordEditor> createState() => _PlanningRecordEditorState();
}

class _PlanningRecordEditorState extends State<PlanningRecordEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  late String frequency, basis, status, debtType;
  String? category;
  bool busy = false, statementConfirmed = false;
  String? error;
  bool get income => widget.kind == 'income';
  bool get debt => widget.kind == 'debts';
  @override
  void initState() {
    super.initState();
    final initial = widget.initial ?? {};
    for (final key in [
      'name',
      'notes',
      'gross',
      'net',
      'amount',
      'outstanding_balance',
      'extra_payment',
      'start_date',
      'end_date',
      'second_day',
    ]) {
      final value = initial[key];
      final monetary = [
        'gross',
        'net',
        'amount',
        'outstanding_balance',
        'extra_payment',
      ].contains(key);
      fields[key] = TextEditingController(
        text: value == null
            ? key == 'start_date'
                  ? dateOf(DateTime.now())
                  : key == 'extra_payment'
                  ? '0'
                  : ''
            : monetary
            ? ((value as num) / 100).toStringAsFixed(2)
            : '$value',
      );
    }
    frequency = initial['frequency'] ?? 'monthly';
    basis = initial['basis'] ?? 'fixed_schedule';
    status = initial['status'] ?? 'active';
    debtType = initial['debt_type'] ?? 'other';
    category = initial['category_id'];
    statementConfirmed = initial['payment_basis'] == 'statement';
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget text(
    String key,
    String label, {
    bool monetary = false,
    bool optional = false,
    bool date = false,
    int maxLength = 80,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: fields[key],
      enabled: !busy,
      keyboardType: monetary
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      maxLength: monetary || date ? null : maxLength,
      decoration: InputDecoration(
        labelText: label,
        helperText: date ? 'YYYY-MM-DD' : null,
      ),
      validator: (value) => monetary
          ? PlanningInputRules.money(value, optional: optional)
          : date
          ? PlanningInputRules.date(value, optional: optional)
          : optional
          ? null
          : InputRules.name(value),
    ),
  );
  Widget choice(
    String label,
    String value,
    List<String> values,
    void Function(String) changed,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: values
          .map(
            (v) =>
                DropdownMenuItem(value: v, child: Text(v.replaceAll('_', ' '))),
          )
          .toList(),
      onChanged: busy ? null : (v) => setState(() => changed(v!)),
    ),
  );
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (debt && debtType == 'credit_card' && !statementConfirmed) {
      setState(
        () => error = 'Confirm that this is the statement-required payment.',
      );
      return;
    }
    final draft = <String, dynamic>{
      'name': fields['name']!.text.trim(),
      'currency': widget.currency,
      'frequency': income && basis == 'monthly_estimate'
          ? 'monthly'
          : frequency,
      'start_date': fields['start_date']!.text,
      'end_date': fields['end_date']!.text.isEmpty
          ? null
          : fields['end_date']!.text,
      'notes': fields['notes']!.text.trim(),
      if (income) ...{
        if (widget.initial?['id'] != null) 'id': widget.initial!['id'],
        'gross': PlanningInputRules.amount(fields['gross']!.text),
        'net': PlanningInputRules.amount(fields['net']!.text),
        'basis': basis,
      } else ...{
        'amount': PlanningInputRules.amount(fields['amount']!.text),
        'category_id': category,
        'status': status,
        'second_day': frequency == 'twice_monthly'
            ? int.tryParse(fields['second_day']!.text)
            : null,
        'debt_type': debtType,
        'outstanding_balance': PlanningInputRules.amount(
          fields['outstanding_balance']!.text,
        ),
        'extra_payment': debt
            ? PlanningInputRules.amount(fields['extra_payment']!.text) ?? 0
            : 0,
        'payment_basis': debtType == 'credit_card' && statementConfirmed
            ? 'statement'
            : 'scheduled',
      },
    };
    setState(() {
      busy = true;
      error = null;
    });
    final saved = await widget.onSave(draft);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        busy = false;
        error = widget.error();
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(
        income
            ? 'Income source'
            : debt
            ? 'Debt schedule'
            : 'Recurring bill',
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                text('name', 'Name'),
                if (income) ...[
                  choice('Income basis', basis, [
                    'fixed_schedule',
                    'monthly_estimate',
                  ], (v) => basis = v),
                  text(
                    'gross',
                    'Gross income (${widget.currency}) · optional',
                    monetary: true,
                    optional: true,
                  ),
                  text(
                    'net',
                    'Net income (${widget.currency}) · optional',
                    monetary: true,
                    optional: true,
                  ),
                  const Text(
                    'Enter gross and take-home amounts separately. Blank means unknown; zero means confirmed zero. Do not include borrowing, transfers or refunds.',
                  ),
                ] else ...[
                  if (debt)
                    choice('Debt type', debtType, [
                      'mortgage',
                      'vehicle',
                      'personal',
                      'education',
                      'credit_card',
                      'bnpl',
                      'other',
                    ], (v) => debtType = v),
                  text(
                    'amount',
                    '${debt ? 'Required payment' : 'Bill amount'} (${widget.currency})${debt ? ' · blank if unknown' : ''}',
                    monetary: true,
                    optional: debt,
                  ),
                  if (debt && debtType == 'credit_card')
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'This is my statement-required payment',
                      ),
                      value: statementConfirmed,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => statementConfirmed = v!),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Expense category',
                    ),
                    items: widget.categories
                        .where((c) => c.type == 'expense')
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        )
                        .toList(),
                    validator: (v) =>
                        v == null ? 'Choose an expense category' : null,
                    onChanged: busy ? null : (v) => category = v,
                  ),
                  const SizedBox(height: 14),
                  if (debt) ...[
                    text(
                      'outstanding_balance',
                      'Outstanding balance · optional',
                      monetary: true,
                      optional: true,
                    ),
                    text(
                      'extra_payment',
                      'Optional extra per payment (${widget.currency})',
                      monetary: true,
                    ),
                    const Text(
                      'Only the required payment forms the debt baseline. Extra repayment is added to the cash obligation. For shared debt, enter only your responsibility and explain it in notes.',
                    ),
                  ],
                ],
                const SizedBox(height: 14),
                if (!(income && basis == 'monthly_estimate'))
                  choice(
                    'Frequency',
                    frequency,
                    widget.kind == 'commitments'
                        ? ['daily', 'weekly', 'monthly']
                        : [
                            'weekly',
                            'fortnightly',
                            'twice_monthly',
                            'monthly',
                            'quarterly',
                            'annually',
                          ],
                    (v) => frequency = v,
                  ),
                if (!income && frequency == 'twice_monthly')
                  text('second_day', 'Second due day (1–31)'),
                text(
                  'start_date',
                  income ? 'Effective start date' : 'First due date',
                  date: true,
                ),
                text(
                  'end_date',
                  'Final effective date · optional',
                  date: true,
                  optional: true,
                ),
                if (!income)
                  choice('Status', status, [
                    'active',
                    'closed',
                  ], (v) => status = v),
                text(
                  'notes',
                  income ? 'Assumptions / explanation' : 'Notes',
                  optional: true,
                  maxLength: 500,
                ),
                if (income && basis == 'monthly_estimate')
                  const Text(
                    'Explain how you chose this monthly estimate. Partial-month activity is not automatically extrapolated.',
                  ),
                if (!income)
                  const Text(
                    'Monthly dates past the end of a short month use its last day, then return to the original day. Closing needs a final effective date and keeps earlier obligations.',
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
          onPressed: busy ? null : save,
          child: Text(busy ? 'Saving…' : 'Save'),
        ),
      ],
    ),
  );
}

class FinancialProfileEditor extends StatefulWidget {
  final PlanningPresenter presenter;
  final String currency;
  const FinancialProfileEditor({
    super.key,
    required this.presenter,
    required this.currency,
  });
  @override
  State<FinancialProfileEditor> createState() => _FinancialProfileEditorState();
}

class _FinancialProfileEditorState extends State<FinancialProfileEditor> {
  final form = GlobalKey<FormState>();
  late final zone = TextEditingController(
    text: widget.presenter.state.profile?['timezone'] ?? '',
  );
  late final sources =
      (widget.presenter.state.profile?['income_sources'] as List? ?? [])
          .map((s) => Map<String, dynamic>.of(s as Json))
          .toList();
  late String confirmation =
      widget.presenter.state.profile?['debt_confirmation'] ?? 'unknown';
  bool confirmed = false, busy = false;
  String? error;
  @override
  void dispose() {
    zone.dispose();
    super.dispose();
  }

  Future<void> sourceEditor([int? index]) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PlanningRecordEditor(
      kind: 'income',
      currency: widget.currency,
      initial: index == null ? null : sources[index],
      error: () => null,
      onSave: (source) async {
        setState(() {
          if (index == null) {
            sources.add(source);
          } else {
            sources[index] = source;
          }
        });
        return true;
      },
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Financial profile'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Account currency: ${widget.currency}'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: zone,
                  enabled: !busy,
                  validator: InputRules.name,
                  decoration: const InputDecoration(
                    labelText: 'Timezone',
                    hintText: 'e.g. Asia/Kuala_Lumpur',
                    helperText:
                        'Enter your IANA timezone; due/overdue dates use it.',
                  ),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < sources.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(sources[i]['name'] as String),
                    subtitle: Text(
                      '${sources[i]['basis']} · ${sources[i]['frequency']}',
                    ),
                    onTap: busy ? null : () => sourceEditor(i),
                    trailing: IconButton(
                      tooltip: 'Remove income source',
                      onPressed: busy
                          ? null
                          : () => setState(() => sources.removeAt(i)),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: busy ? null : sourceEditor,
                  icon: const Icon(Icons.add),
                  label: const Text('Add income source'),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: confirmation,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Debt list confirmation',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'unknown',
                      child: Text('Not reviewed yet'),
                    ),
                    DropdownMenuItem(
                      value: 'complete',
                      child: Text('My listed debts are complete'),
                    ),
                    DropdownMenuItem(
                      value: 'none',
                      child: Text('I have no current debt'),
                    ),
                  ],
                  onChanged: busy ? null : (v) => confirmation = v!,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'I have reviewed these income and debt inputs',
                  ),
                  value: confirmed,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => confirmed = v!),
                ),
                const Text(
                  'You may save an incomplete draft. No missing amount or empty debt list is assumed to mean zero.',
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
          onPressed: busy
              ? null
              : () async {
                  if (!form.currentState!.validate()) return;
                  setState(() {
                    busy = true;
                    error = null;
                  });
                  final saved = await widget.presenter.saveProfile({
                    'timezone': zone.text.trim(),
                    'income_sources': sources,
                    'debt_confirmation': confirmation,
                    'confirmed': confirmed,
                  });
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
          child: Text(busy ? 'Saving…' : 'Save profile'),
        ),
      ],
    ),
  );
}
