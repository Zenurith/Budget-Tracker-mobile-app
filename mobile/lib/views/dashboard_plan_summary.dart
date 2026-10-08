import 'package:flutter/material.dart';
import '../models/finance.dart';

/// Displays server projections without deriving financial decisions in the view.
class DashboardPlanSummary extends StatelessWidget {
  final Json summary;
  final String currency;
  final bool stale;
  final VoidCallback openHelper, openWishlist;
  const DashboardPlanSummary({
    super.key,
    required this.summary,
    required this.currency,
    required this.stale,
    required this.openHelper,
    required this.openWishlist,
  });

  @override
  Widget build(BuildContext context) {
    final review = summary['review'] as Map?;
    final helper = review?['debt_ratios'] as Map?;
    final funding = review?['funding'] as Map?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your financial plan',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (stale)
          const Text(
            'Cached or outdated estimates. Refresh before making a decision.',
          ),
        Text('Debt ratios', style: Theme.of(context).textTheme.titleMedium),
        if (helper == null)
          const Text(
            'Review your declared income and debt schedules to see your ratios.',
          )
        else ...[
          Text(
            'Declared schedules as of ${helper['effective_date']}. These are not historical income records or a borrowing recommendation.',
          ),
          for (final key in ['dsr', 'dti'])
            Text(
              '${key.toUpperCase()} (${key == 'dsr' ? 'net' : 'gross'} income): ${helper['ratios']?[key]?['value'] == null ? 'Needs updated information' : '${helper['ratios'][key]['value']}%'}',
            ),
          if (helper['review_due'] == true)
            const Text('Your income and debt review is due.'),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: openHelper,
            child: const Text('Open financial helper'),
          ),
        ),
        const Divider(),
        Text(
          'Wishlist progress',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (funding == null)
          const Text(
            'Add a wanted purchase and reserve existing cash to start saving.',
          )
        else ...[
          Text('${funding['active_items']} active items'),
          if (funding['active_funded_total'] != null &&
              funding['active_target_total'] != null)
            Text(
              '${money(funding['active_funded_total'], currency)} reserved toward ${money(funding['active_target_total'], currency)} in active targets',
            ),
          Text(
            'All wishlist reservations: ${money(funding['current_reserves']['wishlist_reserved'], currency)}',
          ),
          Text(
            'Current reservations as of ${funding['as_of']}, not historical month-end cash.',
          ),
          if (funding['usable'] != true)
            const Text('Cash and plan need review.'),
        ],
        const Text(
          'Reserved funds alone do not establish purchase readiness. Open your wishlist for an updated review.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: openWishlist,
            child: const Text('Open guilt-free wishlist'),
          ),
        ),
      ],
    );
  }
}
