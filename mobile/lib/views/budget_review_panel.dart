import 'dart:async';
import 'package:flutter/material.dart';
import '../core/view/presenter_builder.dart';
import '../features/budgets/presenter/budget_review_presenter.dart';
import '../models/finance.dart';

class BudgetReviewPanel extends StatefulWidget {
  final BudgetReviewPresenter presenter;
  final Future<void> Function(Json) adjust;
  final Future<void> Function(Json) transactions;
  final VoidCallback close;
  const BudgetReviewPanel({
    super.key,
    required this.presenter,
    required this.adjust,
    required this.transactions,
    required this.close,
  });
  @override
  State<BudgetReviewPanel> createState() => _BudgetReviewPanelState();
}

class _BudgetReviewPanelState extends State<BudgetReviewPanel> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PresenterBuilder(
    presenter: widget.presenter,
    builder: (context, state) {
      final p = widget.presenter;
      if (p.target == null) {
        return TextButton(
          onPressed: widget.close,
          child: const Text('All budgets'),
        );
      }
      final data = state.data;
      final items = (data?['items'] as List? ?? []).cast<Json>();
      final selected = items
          .where((item) => p.target!.ids.contains(item['id']))
          .toList();
      final missing = p.target!.ids.toSet().difference(
        items.map((item) => item['id'] as String).toSet(),
      );
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Budget review · ${p.target!.period}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: widget.close,
                    child: const Text('All budgets'),
                  ),
                  TextButton(
                    onPressed: state.busy ? null : p.refresh,
                    child: const Text('Refresh review'),
                  ),
                ],
              ),
              if (state.busy)
                const LinearProgressIndicator(
                  semanticsLabel: 'Loading budget review',
                ),
              if (!state.busy && !p.usable)
                Text(
                  state.error ??
                      'Refresh to see current spending and your daily guide.',
                ),
              if (p.usable && data != null) ...[
                Text('Checked ${data['as_of']}'),
                if (data['timezone'] != null)
                  Text('Calendar timezone: ${data['timezone']}'),
                if (data['days_remaining'] != null)
                  Text('${data['days_remaining']} days left, including today.'),
                if (missing.isNotEmpty)
                  const Text(
                    'Some budgets from this alert were removed or are no longer available.',
                  ),
                for (final budget in selected) ...[
                  const Divider(height: 32),
                  Text(
                    budget['name'],
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Spent ${money(budget['spent'], data['currency'])} of ${money(budget['limit_amount'], data['currency'])}',
                  ),
                  Text(
                    budget['remaining'] < 0
                        ? '${money(-budget['remaining'], data['currency'])} over budget'
                        : '${money(budget['remaining'], data['currency'])} remaining',
                  ),
                  Text(
                    budget['threshold_reached'] == true
                        ? '${budget['alert_threshold']}% alert threshold reached.'
                        : 'Spending is now below the ${budget['alert_threshold']}% alert threshold.',
                  ),
                  if (budget['daily_guide'] != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${money(budget['daily_guide'], data['currency'])} per day for the rest of this month',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text(
                      'Remaining budget divided by days left, including today, rounded down. This is a budgeting guide, not verified cash available to spend. Do not add overlapping overall and category guides together.',
                    ),
                  ] else
                    Text(
                      data['timezone'] == null
                          ? 'Set your financial profile timezone to see a daily guide.'
                          : 'Daily guides are available for the current month only.',
                    ),
                  const SizedBox(height: 12),
                  const Text('Top spending categories'),
                  if ((budget['top_categories'] as List).isEmpty)
                    const Text('No recorded expenses for this budget.'),
                  for (final category in budget['top_categories'])
                    Text(
                      '${category['name']}: ${money(category['amount'], data['currency'])}',
                    ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => widget.transactions(budget),
                        child: const Text('Review transactions'),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          await widget.adjust(budget);
                          if (mounted) await p.refresh();
                        },
                        child: const Text('Adjust limit'),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      );
    },
  );
}
