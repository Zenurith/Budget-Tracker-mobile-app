import 'dart:async';
import '../features/debt_planner/presenter/scenario_presenter.dart';
import 'package:flutter/material.dart';
import '../features/debt_planner/model/repayment_plan.dart';
import '../features/planning/model/input_rules.dart';
import '../models/finance.dart';

class DebtPlannerScreen extends StatefulWidget {
  final String currency;
  final ScenarioPresenter? presenter;
  const DebtPlannerScreen({super.key, required this.currency, this.presenter});
  @override
  State<DebtPlannerScreen> createState() => _DebtPlannerScreenState();
}

class _DebtInputs {
  final name = TextEditingController(),
      balance = TextEditingController(),
      rate = TextEditingController(),
      minimum = TextEditingController();
  void dispose() {
    for (final c in [name, balance, rate, minimum]) {
      c.dispose();
    }
  }
}

class _DebtPlannerScreenState extends State<DebtPlannerScreen> {
  StreamSubscription<ScenarioState>? subscription;
  String? owner;
  String? scenarioNotice;
  final scenarioName = TextEditingController();
  @override
  void initState() {
    super.initState();
    owner = widget.presenter?.owner;
    subscription = widget.presenter?.states.listen((_) {
      if (!mounted) return;
      if (owner != widget.presenter?.owner) {
        owner = widget.presenter?.owner;
        replaceInputs([], '', '', '');
      } else {
        setState(() {});
      }
    });
    widget.presenter?.reload();
  }

  void replaceInputs(
    List<dynamic> rows,
    String month,
    String extraValue,
    String name,
  ) {
    final old = List<_DebtInputs>.of(debts);
    setState(() {
      debts.clear();
      for (final row in rows) {
        final d = _DebtInputs();
        d.name.text = row['name'] as String;
        String amount(dynamic value) =>
            value == null ? '' : ((value as int) / 100).toStringAsFixed(2);
        d.balance.text = amount(row['balance']);
        d.rate.text = amount(row['rate']);
        d.minimum.text = amount(row['minimum']);
        debts.add(d);
      }
      if (debts.isEmpty) debts.add(_DebtInputs());
      firstMonth.text = month;
      extra.text = extraValue;
      scenarioName.text = name;
      scenarioNotice = null;
      snowball = avalanche = baseline = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final d in old) {
        d.dispose();
      }
    });
  }

  Future<bool> confirmReplace() async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Replace planner inputs?'),
          content: const Text(
            'Unsaved inputs will be replaced. Your real debt records are unchanged.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Replace inputs'),
            ),
          ],
        ),
      ) ==
      true;
  final form = GlobalKey<FormState>();
  final debts = <_DebtInputs>[_DebtInputs()];
  final extra = TextEditingController(), firstMonth = TextEditingController();
  List<RepaymentDebt>? calculatedDebts;
  RepaymentResult? snowball, avalanche, baseline;
  DateTime? start;
  void invalidate() {
    setState(() {
      snowball = avalanche = baseline = null;
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    scenarioName.dispose();
    for (final debt in debts) {
      debt.dispose();
    }
    extra.dispose();
    firstMonth.dispose();
    super.dispose();
  }

  String monthLabel(int months) {
    final date = DateTime(start!.year, start!.month + months - 1);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }

  Widget field(
    TextEditingController controller,
    String label, {
    bool name = false,
    bool month = false,
    bool rate = false,
    bool zero = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: name || month
          ? TextInputType.text
          : const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => invalidate(),
      validator: (value) {
        final text = (value ?? '').trim();
        if (name) {
          return text.isEmpty || text.length > 80
              ? 'Enter a name (1–80 characters)'
              : null;
        }
        if (month) {
          final date = DateTime.tryParse('$text-01');
          return !RegExp(r'^\d{4}-\d{2}$').hasMatch(text) ||
                  date == null ||
                  date.year < 1900 ||
                  date.year > 9400 ||
                  date.month.toString().padLeft(2, '0') != text.substring(5)
              ? 'Use YYYY-MM, between 1900 and 9400'
              : null;
        }
        final amount = PlanningInputRules.amount(text);
        if (amount == null ||
            amount < (zero || rate ? 0 : 1) ||
            amount > (rate ? 10000 : 100000000000)) {
          return rate
              ? 'Enter an annual rate from 0 to 100%, up to 2 decimals'
              : 'Enter ${zero ? 'zero or a positive' : 'a positive'} amount, up to 2 decimals';
        }
        return null;
      },
    ),
  );
  Widget result(String title, RepaymentResult r) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          Text(
            r.paidOff
                ? 'Estimated debt-free: ${monthLabel(r.months)} · ${r.months} months'
                : 'Not paid off within the simulation limit (${r.months} months).',
          ),
          Text(
            'Interest ${r.paidOff ? 'total' : 'through simulated months'}: ${money(r.interest, widget.currency)}',
          ),
          if (!r.paidOff)
            Text('Remaining debt: ${money(r.remaining, widget.currency)}'),
          for (var i = 0; i < calculatedDebts!.length; i++)
            Text(
              '${calculatedDebts![i].name}: ${r.payoffMonths[i] == null ? 'not paid off' : monthLabel(r.payoffMonths[i]!)}',
            ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Debt repayment planner')),
    body: AbsorbPointer(
      absorbing: widget.presenter?.state.busy == true,
      child: Form(
        key: form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Compare smallest-balance-first (snowball) and highest-rate-first (avalanche). Enter current balances, annual interest rates and fixed monthly minimum payments explicitly. This scenario does not change your debts or verify that you can afford these payments.',
              ),
              const Text(
                'Assumptions: interest accrues monthly before payment at annual rate ÷ 12, rounded to cents; rates and minimums stay fixed. Freed payments roll into other debts. No fees, new borrowing, promotional rates or daily interest. Maximum 600 months; very large growing balances stop earlier.',
              ),
              if (widget.presenter != null) ...[
                if (widget.presenter!.state.busy)
                  const LinearProgressIndicator(),
                if (widget.presenter!.state.error != null)
                  Text(widget.presenter!.state.error!),
                if (scenarioNotice != null) Text(scenarioNotice!),
                const Text(
                  'Saved scenarios are snapshots, not current debt balances. Confirm balances, rates, minimum payments and dates before recalculating. Rates are not stored in debt schedules; non-monthly payments are left blank.',
                ),
                OutlinedButton(
                  onPressed: () async {
                    final p = widget.presenter!;
                    final originalOwner = p.owner;
                    if (!await confirmReplace() ||
                        !mounted ||
                        p.owner != originalOwner) {
                      return;
                    }
                    if (!await p.reload() ||
                        !mounted ||
                        p.owner != originalOwner) {
                      return;
                    }
                    final rows = p.state.data['debts'] as List;
                    if (rows.length > 20) {
                      setState(
                        () => scenarioNotice =
                            'More than 20 active debts. Enter the debts to compare manually.',
                      );
                      return;
                    }
                    replaceInputs(
                      rows,
                      (p.state.data['as_of'] as String).substring(0, 7),
                      '',
                      '',
                    );
                    setState(
                      () => scenarioNotice = rows.isEmpty
                          ? 'No active saved debts found.'
                          : 'Imported ${rows.length} debts. Balances are declared values, not automatically reduced by payments. Confirm every amount and supply missing rates. Extra payment is left blank.',
                    );
                  },
                  child: const Text('Import saved debts'),
                ),
                OutlinedButton(
                  onPressed: widget.presenter!.reload,
                  child: const Text('Refresh saved scenarios'),
                ),
                for (final saved
                    in widget.presenter!.state.data['scenarios'] as List? ?? [])
                  ListTile(
                    title: Text(saved['name']),
                    subtitle: Text('Saved ${saved['created_at']}'),
                    onTap: () async {
                      final p = widget.presenter!;
                      final originalOwner = p.owner;
                      if (!await confirmReplace() ||
                          !mounted ||
                          originalOwner != p.owner) {
                        return;
                      }
                      replaceInputs(
                        saved['debts'] as List,
                        saved['first_month'],
                        ((saved['extra'] as int) / 100).toStringAsFixed(2),
                        saved['name'],
                      );
                      setState(
                        () => scenarioNotice =
                            'Loaded saved assumptions. Review for changes before calculating.',
                      );
                    },
                    trailing: IconButton(
                      tooltip: 'Delete scenario',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final p = widget.presenter!;
                        final originalOwner = p.owner;
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text('Delete ${saved['name']}?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (yes == true &&
                            mounted &&
                            p.owner == originalOwner) {
                          await p.delete(saved['id']);
                        }
                      },
                    ),
                  ),
                TextField(
                  controller: scenarioName,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Scenario name (for saving)',
                  ),
                ),
                OutlinedButton(
                  onPressed: () async {
                    if (!form.currentState!.validate()) return;
                    if (scenarioName.text.trim().isEmpty) {
                      setState(
                        () => scenarioNotice =
                            'Enter a scenario name before saving.',
                      );
                      return;
                    }
                    final p = widget.presenter!;
                    final originalOwner = p.owner;
                    final ok = await p.save({
                      'name': scenarioName.text.trim(),
                      'currency': widget.currency,
                      'first_month': firstMonth.text.trim(),
                      'extra': PlanningInputRules.amount(extra.text),
                      'debts': debts
                          .map(
                            (d) => {
                              'name': d.name.text.trim(),
                              'balance': PlanningInputRules.amount(
                                d.balance.text,
                              ),
                              'rate': PlanningInputRules.amount(d.rate.text),
                              'minimum': PlanningInputRules.amount(
                                d.minimum.text,
                              ),
                            },
                          )
                          .toList(),
                    });
                    if (mounted && p.owner == originalOwner && ok) {
                      setState(
                        () => scenarioNotice =
                            'Scenario saved to your account. Real debt records are unchanged.',
                      );
                    }
                  },
                  child: const Text('Save scenario snapshot'),
                ),
              ],
              field(firstMonth, 'First payment month (YYYY-MM)', month: true),
              for (var i = 0; i < debts.length; i++)
                Card(
                  key: ObjectKey(debts[i]),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        field(debts[i].name, 'Debt ${i + 1} name', name: true),
                        field(
                          debts[i].balance,
                          'Current balance (${widget.currency})',
                        ),
                        field(
                          debts[i].rate,
                          'Annual interest rate (%)',
                          rate: true,
                        ),
                        field(
                          debts[i].minimum,
                          'Monthly minimum payment (${widget.currency})',
                        ),
                        if (debts.length > 1)
                          TextButton(
                            onPressed: () {
                              final removed = debts.removeAt(i);
                              invalidate();
                              WidgetsBinding.instance.addPostFrameCallback(
                                (_) => removed.dispose(),
                              );
                            },
                            child: const Text('Remove debt'),
                          ),
                      ],
                    ),
                  ),
                ),
              OutlinedButton(
                onPressed: debts.length >= 20
                    ? null
                    : () {
                        debts.add(_DebtInputs());
                        invalidate();
                      },
                child: const Text('Add debt'),
              ),
              field(
                extra,
                'Extra monthly payment (${widget.currency}) — enter 0 if none',
                zero: true,
              ),
              FilledButton(
                onPressed: () {
                  if (!form.currentState!.validate()) return;
                  final inputs = debts
                      .map(
                        (d) => RepaymentDebt(
                          d.name.text.trim(),
                          PlanningInputRules.amount(d.balance.text)!,
                          PlanningInputRules.amount(d.rate.text)!,
                          PlanningInputRules.amount(d.minimum.text)!,
                        ),
                      )
                      .toList();
                  final additional = PlanningInputRules.amount(extra.text)!;
                  setState(() {
                    calculatedDebts = inputs;
                    start = DateTime.parse('${firstMonth.text.trim()}-01');
                    snowball = simulateRepayment(
                      inputs,
                      additional,
                      avalanche: false,
                    );
                    avalanche = simulateRepayment(
                      inputs,
                      additional,
                      avalanche: true,
                    );
                    baseline = simulateRepayment(inputs, 0, avalanche: true);
                  });
                },
                child: const Text('Compare repayment plans'),
              ),
              if (snowball != null) ...[
                Text(
                  'Fixed monthly budget: ${money(calculatedDebts!.fold<int>(PlanningInputRules.amount(extra.text)!, (s, d) => s + d.minimumPayment), widget.currency)}',
                ),
                result('Snowball', snowball!),
                result('Avalanche', avalanche!),
                if (baseline!.paidOff && avalanche!.paidOff)
                  Text(
                    'Compared with avalanche without extra payments: ${baseline!.months - avalanche!.months} fewer months and ${money(baseline!.interest - avalanche!.interest, widget.currency)} less interest.',
                  ),
                result('Baseline: avalanche with no extra payment', baseline!),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
