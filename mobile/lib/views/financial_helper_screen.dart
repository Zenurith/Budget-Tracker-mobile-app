import 'package:flutter/material.dart';
import '../core/view/presenter_builder.dart';
import '../features/financial_helper/presenter/helper_presenter.dart';
import '../features/planning/model/input_rules.dart';
import '../models/finance.dart';

class FinancialHelperScreen extends StatefulWidget {
  final HelperPresenter presenter;
  const FinancialHelperScreen({super.key, required this.presenter});
  @override
  State<FinancialHelperScreen> createState() => _FinancialHelperScreenState();
}

class _FinancialHelperScreenState extends State<FinancialHelperScreen> {
  HelperPresenter get p => widget.presenter;
  @override
  void initState() {
    super.initState();
    p.reload();
  }

  Future<void> save(bool scenario) async {
    final controller = TextEditingController(
      text: scenario ? 'What-if scenario' : 'Debt ratio baseline',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save a snapshot'),
        content: TextField(
          controller: controller,
          maxLength: 80,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Snapshot name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (name == null || !mounted) return;
    final ok = await p.save(name, scenario: scenario);
    if (mounted && ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Snapshot saved')));
    }
  }

  @override
  Widget build(BuildContext context) => PresenterBuilder(
    presenter: p,
    builder: (context, state) => Scaffold(
      appBar: AppBar(
        title: const Text('Financial helper'),
        actions: [
          IconButton(
            tooltip: 'Refresh calculations',
            onPressed: state.saving ? null : p.reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Understand your scheduled debt payments relative to your declared income. These personal estimates do not predict loan approval.',
          ),
          const SizedBox(height: 12),
          if (state.busy || state.saving)
            const LinearProgressIndicator(
              semanticsLabel: 'Loading financial helper',
            ),
          if (state.stale)
            const Text(
              'Inputs may have changed. Refresh before trying or saving a scenario.',
            ),
          if (state.error != null) ...[
            Text(
              state.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: state.saving ? null : p.reload,
              child: const Text('Retry / refresh'),
            ),
          ],
          if (state.baseline.isNotEmpty) ...[
            HelperResultCard(
              result: state.baseline,
              title: state.scenario.isEmpty
                  ? 'Current baseline'
                  : 'Baseline at scenario date',
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: state.canSave
                      ? () => showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => HelperScenarioEditor(presenter: p),
                        )
                      : null,
                  child: const Text('Try a what-if scenario'),
                ),
                OutlinedButton(
                  onPressed: state.canSave ? () => save(false) : null,
                  child: const Text('Save baseline snapshot'),
                ),
              ],
            ),
            if (state.scenario.isNotEmpty) ...[
              HelperResultCard(result: state.scenario, title: 'What-if result'),
              Wrap(
                spacing: 12,
                children: [
                  FilledButton(
                    onPressed: state.canSave ? () => save(true) : null,
                    child: const Text('Save scenario snapshot'),
                  ),
                  TextButton(
                    onPressed: state.busy || state.saving
                        ? null
                        : p.discardScenario,
                    child: const Text('Discard scenario'),
                  ),
                ],
              ),
            ],
          ],
          const SizedBox(height: 24),
          Text(
            'Saved snapshots',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Saved results preserve the inputs and assumptions from that calculation.',
          ),
          if (state.snapshots.isEmpty && !state.busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No saved snapshots yet.'),
            ),
          for (final saved in state.snapshots)
            Card(
              child: ExpansionTile(
                title: Text(saved['name'] as String),
                subtitle: Text(
                  '${(saved['result'] as Json)['effective_date']} · ${saved['outdated'] == true ? 'Outdated inputs' : 'Inputs unchanged'}${saved['review_due'] == true ? ' · Review due' : ''}',
                ),
                children: [
                  HelperResultCard(
                    result: saved['result'] as Json,
                    title:
                        'Saved ${((saved['result'] as Json)['kind'] ?? 'baseline')}',
                  ),
                ],
              ),
            ),
          if (state.hasMore)
            TextButton(
              onPressed: state.busy || state.saving ? null : p.loadMore,
              child: const Text('Load more snapshots'),
            ),
        ],
      ),
    ),
  );
}

String helperMoney(dynamic value, String currency) {
  if (value == null) return 'Unavailable';
  // Display only: authoritative arithmetic and percentage rounding stay on the server.
  return '$currency ${(double.parse(value.toString()) / 100).toStringAsFixed(2)}';
}

class HelperResultCard extends StatelessWidget {
  final Json result;
  final String title;
  const HelperResultCard({
    super.key,
    required this.result,
    required this.title,
  });
  @override
  Widget build(BuildContext context) {
    final currency = result['currency'] as String;
    final ratios = result['ratios'] as Json;
    String amount(String key) => helperMoney(result[key], currency);
    String ratio(String key) => (ratios[key] as Json)['value'] == null
        ? 'Unavailable'
        : '${ratios[key]['value']}%';
    final assumptions = result['assumptions'] as Json?;
    final debtNames = {
      for (final debt in result['debts'] as List? ?? [])
        debt['id']: debt['name'],
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            Text('Effective ${result['effective_date']}'),
            Text(
              result['complete'] == true
                  ? 'Inputs complete'
                  : 'Inputs incomplete — review the details below',
            ),
            if (result['review_due'] == true) const Text('Profile review due'),
            const SizedBox(height: 12),
            Text(
              'DSR · net income basis: ${ratio('dsr')}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'DTI · gross income basis: ${ratio('dti')}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final key in ['dsr', 'dti'])
              if (ratios[key]['target'] != null)
                Text(
                  '${key.toUpperCase()} personal target: ${ratios[key]['target']}% · difference ${ratios[key]['distance_to_target'] ?? 'unavailable'} percentage points (positive = above target)',
                ),
            Text('Income after debt: ${amount('income_after_debt')}'),
            const Text('Essentials and savings have not been deducted.'),
            for (final missing in result['missing_inputs'] as List? ?? [])
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('• ${missing['message']}'),
              ),
            for (final warning in result['warnings'] as List? ?? [])
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(warning as String),
              ),
            if (assumptions != null) ...[
              const SizedBox(height: 12),
              Text(
                'Scenario gross income: ${assumptions['gross_monthly'] == null ? 'Use declared sources' : helperMoney(assumptions['gross_monthly'], currency)}',
              ),
              Text(
                'Scenario net income: ${assumptions['net_monthly'] == null ? 'Use declared sources' : helperMoney(assumptions['net_monthly'], currency)}',
              ),
              Text(
                'Additional monthly payment: ${helperMoney(assumptions['additional_debt_monthly'], currency)}',
              ),
              for (final change in assumptions['debt_payments'] as List? ?? [])
                Text(
                  '${debtNames[change[0]] ?? 'Changed debt'}: ${helperMoney(change[1], currency)} per month',
                ),
              if ((assumptions['notes'] as String? ?? '').isNotEmpty)
                Text(assumptions['notes'] as String),
            ],
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Show arithmetic and inputs'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Required monthly debt: ${amount('debt_monthly')}'),
                      Text('Net monthly income: ${amount('net_monthly')}'),
                      Text('Gross monthly income: ${amount('gross_monthly')}'),
                      const Text(
                        'DSR = required monthly debt ÷ net monthly income × 100\nDTI = required monthly debt ÷ gross monthly income × 100',
                      ),
                      const Text(
                        'Monthly conversion: weekly × 52/12; fortnightly × 26/12; twice monthly × 2; quarterly ÷ 3; annual ÷ 12. Display amounts are rounded; calculations retain precision.',
                      ),
                      for (final debt in result['debts'] as List? ?? [])
                        Text(
                          '${debt['name']}: ${helperMoney(debt['amount'], currency)} ${debt['frequency']} → ${helperMoney(debt['monthly_payment'], currency)}/month',
                        ),
                      for (final income
                          in result['income_sources'] as List? ?? [])
                        Text(
                          '${income['name']} (${income['basis']}): gross ${helperMoney(income['gross_monthly'], currency)}, net ${helperMoney(income['net_monthly'], currency)}/month',
                        ),
                      Text(
                        'Last user review: ${result['reviewed_at'] ?? 'Not confirmed'}',
                      ),
                      Text(
                        'Calculated: ${result['calculated_at'] ?? ''} · ${result['formula_version'] ?? ''}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class HelperScenarioEditor extends StatefulWidget {
  final HelperPresenter presenter;
  const HelperScenarioEditor({super.key, required this.presenter});
  @override
  State<HelperScenarioEditor> createState() => _HelperScenarioEditorState();
}

class _HelperScenarioEditorState extends State<HelperScenarioEditor> {
  final form = GlobalKey<FormState>();
  final gross = TextEditingController(),
      net = TextEditingController(),
      extra = TextEditingController(text: '0'),
      notes = TextEditingController();
  late final date = TextEditingController(
    text: widget.presenter.state.baseline['effective_date'] as String,
  );
  late final debts = {
    for (final debt in widget.presenter.state.baseline['debts'] as List)
      debt['id'] as String: TextEditingController(),
  };
  bool busy = false;
  String? error;
  @override
  void dispose() {
    for (final c in [gross, net, extra, notes, date, ...debts.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget moneyField(
    TextEditingController controller,
    String label, {
    bool optional = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      enabled: !busy,
      decoration: InputDecoration(
        labelText: label,
        helperText: optional
            ? 'Leave blank to use the declared schedule'
            : null,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (v) => optional && (v ?? '').trim().isEmpty
          ? null
          : PlanningInputRules.money(v),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('What if my income or payments change?'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Compare hypothetical monthly amounts. Your real profile, debts and transactions stay as entered.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: date,
                  enabled: !busy,
                  validator: PlanningInputRules.date,
                  decoration: const InputDecoration(
                    labelText: 'Effective date (YYYY-MM-DD)',
                  ),
                ),
                const SizedBox(height: 16),
                moneyField(
                  gross,
                  'Gross monthly income (${widget.presenter.state.baseline['currency']})',
                ),
                moneyField(
                  net,
                  'Net monthly income (${widget.presenter.state.baseline['currency']})',
                ),
                moneyField(
                  extra,
                  'Additional monthly debt payment',
                  optional: false,
                ),
                for (final debt
                    in widget.presenter.state.baseline['debts'] as List)
                  moneyField(
                    debts[debt['id']]!,
                    '${debt['name']} · replace monthly payment',
                  ),
                TextFormField(
                  controller: notes,
                  enabled: !busy,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Assumptions / explanation',
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
          onPressed: busy
              ? null
              : () async {
                  if (!form.currentState!.validate()) return;
                  setState(() {
                    busy = true;
                    error = null;
                  });
                  final ok = await widget.presenter.preview({
                    if (gross.text.trim().isNotEmpty)
                      'gross_monthly': PlanningInputRules.amount(gross.text),
                    if (net.text.trim().isNotEmpty)
                      'net_monthly': PlanningInputRules.amount(net.text),
                    'additional_debt_monthly': PlanningInputRules.amount(
                      extra.text,
                    ),
                    'notes': notes.text,
                    'debt_payments': [
                      for (final entry in debts.entries)
                        if (entry.value.text.trim().isNotEmpty)
                          {
                            'id': entry.key,
                            'monthly_payment': PlanningInputRules.amount(
                              entry.value.text,
                            ),
                          },
                    ],
                  }, date.text.trim());
                  if (!context.mounted) return;
                  if (ok) {
                    Navigator.pop(context);
                  } else {
                    setState(() {
                      busy = false;
                      error =
                          widget.presenter.state.error ??
                          'Refresh the helper and try again.';
                    });
                  }
                },
          child: Text(busy ? 'Calculating…' : 'Compare scenario'),
        ),
      ],
    ),
  );
}
