import 'package:flutter/material.dart';
import '../core/presentation/app_presenters.dart';
import '../core/view/presenter_builder.dart';
import '../models/finance.dart';
import 'funding_screen.dart';
import 'planning_screen.dart';
import 'planning_editors.dart';

/// Resumes from saved financial records; opening or leaving never saves inputs.
class SetupScreen extends StatefulWidget {
  final AppPresenters presenters;
  final Future<void> Function(String month) editBudget;
  const SetupScreen({
    super.key,
    required this.presenters,
    required this.editBudget,
  });
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool working = false;
  String? error;
  static const labels = {
    'cash': (
      'Confirm your balances',
      'List the cash, bank and e-wallet balances included in your plan.',
    ),
    'income': (
      'Review your income',
      'Enter gross and take-home income, your timezone and your debt confirmation. Zero income can be entered explicitly.',
    ),
    'commitments': (
      'Add bills and debts',
      'Add recurring commitments in Financial plan. Then review the funding plan to confirm the list, including when there are none.',
    ),
    'budget': (
      'Set this month’s budget',
      'Choose an overall spending limit or a category budget for the current month.',
    ),
    'savings': (
      'Create a savings goal (optional)',
      'Give emergency savings or another goal a name. Creating a goal does not reserve money.',
    ),
    'review': (
      'Review cash and protection',
      'Confirm the next income date or 30-day horizon, essential allowances and buffer. Reconcile again if your cash has changed.',
    ),
  };

  Future<void> open(String id) async {
    setState(() {
      working = true;
      error = null;
    });
    final p = widget.presenters;
    try {
      if (id == 'budget') {
        await widget.editBudget(p.overview.setup['budget_month'] as String);
      } else if (id == 'commitments') {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => PlanningScreen(presenters: p),
          ),
        );
      } else if (id == 'income') {
        await p.planning.reload();
        if (!mounted) return;
        if (p.planning.state.error != null) {
          throw StateError(p.planning.state.error!);
        }
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => FinancialProfileEditor(
            presenter: p.planning,
            currency: p.overview.currency,
          ),
        );
      } else {
        await p.funding.reload();
        if (!mounted) return;
        if (!p.funding.state.editable) {
          throw StateError(
            p.funding.state.error ?? 'Connect and reload your funding plan.',
          );
        }
        if (id == 'review') {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => FundingScreen(presenter: p.funding),
            ),
          );
        } else {
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => FundingEditor(
              presenter: p.funding,
              mode: id == 'cash' ? 'snapshot' : 'goal',
            ),
          );
        }
      }
      await p.overview.reload();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) => PresenterBuilder(
    presenter: widget.presenters.overview,
    builder: (context, state) {
      final p = widget.presenters.overview;
      final steps = (p.setup['steps'] as List? ?? []).cast<Json>();
      final required = steps.where((s) => s['optional'] != true).toList();
      final completed = required.where((s) => s['done'] == true).length;
      final unavailable = state.stale || state.data.cachedAt != null;
      return Scaffold(
        appBar: AppBar(title: const Text('Set up Pocketwise')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Make Pocketwise yours',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Take one step at a time, in any order. Each saved step is kept when you leave.',
            ),
            const SizedBox(height: 12),
            if (state.busy || working) const LinearProgressIndicator(),
            if (unavailable)
              const Text(
                'Progress may be out of date. Refresh online to continue setup.',
              ),
            if (state.error != null) Text(state.error!),
            if (error != null) Text(error!),
            if (steps.isEmpty || unavailable)
              TextButton(
                onPressed: working || state.busy ? null : p.reload,
                child: const Text('Reload setup'),
              ),
            if (required.isNotEmpty)
              Text('$completed of ${required.length} required steps complete'),
            if (p.setup['complete'] == true)
              const Text(
                'Your setup is complete. You can review or change any step below.',
              ),
            for (final step in steps)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        labels[step['id']]!.$1,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        step['done'] == true
                            ? 'Complete'
                            : step['optional'] == true
                            ? 'Optional'
                            : 'To do',
                      ),
                      const SizedBox(height: 6),
                      Text(labels[step['id']]!.$2),
                      if (step['id'] == 'budget')
                        Text('Budget month: ${p.setup['budget_month']}'),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: working || state.busy || unavailable
                              ? null
                              : () => open(step['id'] as String),
                          child: Text(
                            step['done'] == true
                                ? 'Review step'
                                : 'Continue step',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            TextButton(
              onPressed: working ? null : () => Navigator.pop(context),
              child: const Text('Continue later'),
            ),
          ],
        ),
      );
    },
  );
}
