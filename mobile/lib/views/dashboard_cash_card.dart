import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/view/presenter_builder.dart';
import '../features/overview/presenter/overview_presenter.dart';
import '../features/sync/presenter/sync_presenter.dart';
import '../models/finance.dart';

class DashboardCashCard extends StatefulWidget {
  final OverviewPresenter presenter;
  final SyncPresenter? sync;
  final VoidCallback openFunding, openSetup;
  const DashboardCashCard({
    super.key,
    required this.presenter,
    this.sync,
    required this.openFunding,
    required this.openSetup,
  });

  @override
  State<DashboardCashCard> createState() => _DashboardCashCardState();
}

class _DashboardCashCardState extends State<DashboardCashCard> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PresenterBuilder(
    presenter: widget.presenter,
    builder: (context, _) => widget.sync == null
        ? content(context)
        : PresenterBuilder(
            presenter: widget.sync!,
            builder: (context, _) => content(context),
          ),
  );

  Widget content(BuildContext context) {
    final p = widget.presenter;
    final cash = p.availability;
    final sync = widget.sync?.state;
    final blocked =
        sync != null &&
        (sync.offline || sync.busy || sync.operations.isNotEmpty);
    final usable = p.availabilityUsable(syncBlocked: blocked);
    final setup = p.setup;
    final payday = cash['next_income_date'];
    String reviewed(Object? value) {
      final date = DateTime.tryParse('$value');
      return date == null
          ? 'Not confirmed'
          : '${DateFormat('d MMM y, HH:mm').format(date.toUtc())} UTC';
    }

    final reasons = [
      ...cash['missing_inputs'] as List? ?? [],
      ...cash['stale_reasons'] as List? ?? [],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          payday == null
              ? 'Available for the next 30 days'
              : 'Available until payday',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          usable ? money(cash['free_to_allocate'], p.currency) : 'Needs review',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        if (usable) ...[
          Text('Through ${cash['horizon_end']} (inclusive) · current plan'),
          const Text(
            'Unallocated cash after your commitments, essentials, savings and buffer.',
          ),
          if ((cash['coverage_shortfall'] as num? ?? 0) > 0)
            Text(
              'Your plan is short by ${money(cash['coverage_shortfall'], p.currency)}. No unallocated cash remains.',
            ),
          Text('Cash reviewed: ${reviewed(cash['cash_reviewed_at'])}'),
          Text('Plan reviewed: ${reviewed(cash['plan_reviewed_at'])}'),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('See the breakdown'),
            children: [
              for (final entry in const {
                'liquid_total': 'Confirmed cash',
                'scheduled_obligations': 'Unpaid bills and debts',
                'essential_allowances': 'Additional essentials',
                'required_savings': 'Required savings still to fund',
                'emergency_reserved': 'Emergency savings reserved',
                'savings_reserved': 'Other savings reserved',
                'wishlist_reserved': 'Wishlist reservations',
                'buffer_amount': 'Cash buffer',
              }.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value),
                  subtitle: Text(money(cash[entry.key], p.currency)),
                ),
            ],
          ),
        ] else ...[
          if (p.busy) const LinearProgressIndicator(),
          Text(
            blocked
                ? 'Connect and finish syncing your transactions before reviewing available cash.'
                : p.state.stale || p.state.data.cachedAt != null
                ? 'These records may be out of date. Refresh online before reviewing available cash.'
                : 'Confirm your cash and review your plan to see an up-to-date amount.',
          ),
          for (final reason in reasons) Text('• $reason'),
          TextButton(
            onPressed: p.busy ? null : p.reload,
            child: const Text('Refresh available cash'),
          ),
        ],
        const Text(
          'Based on manually confirmed balances. Expected income adds no available cash.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: widget.openFunding,
              child: const Text('Review cash & plan'),
            ),
            OutlinedButton(
              onPressed: widget.openSetup,
              child: Text(
                setup['complete'] == true
                    ? 'Review setup'
                    : 'Set up Pocketwise',
              ),
            ),
          ],
        ),
        if (setup.isNotEmpty && setup['complete'] != true)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'A few steps will connect your income, bills and budget. Continue whenever you’re ready.',
            ),
          ),
      ],
    );
  }
}
