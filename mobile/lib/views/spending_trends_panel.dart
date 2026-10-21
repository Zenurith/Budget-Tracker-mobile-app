import 'package:flutter/material.dart';
import '../features/reports/model/spending_trends.dart';
import '../models/finance.dart';

class SpendingTrendsPanel extends StatefulWidget {
  final List<Json> months;
  final String currency;
  final String Function(String) categoryName;
  final bool cached;
  const SpendingTrendsPanel({
    super.key,
    required this.months,
    required this.currency,
    required this.categoryName,
    this.cached = false,
  });
  @override
  State<SpendingTrendsPanel> createState() => _SpendingTrendsPanelState();
}

class _SpendingTrendsPanelState extends State<SpendingTrendsPanel> {
  int count = 3;
  @override
  Widget build(BuildContext context) {
    final trend = SpendingTrends(widget.months, count);
    String amount(int value) => money(value, widget.currency);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Spending trends', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final n in [3, 6])
              ChoiceChip(
                label: Text('$n months'),
                selected: count == n,
                onSelected: (_) => setState(() => count = n),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.cached)
          const Text('Cached estimates · reconnect to refresh.'),
        const Text(
          'Recorded activity only. No entries does not confirm zero spending. Compare periods with similar recording coverage.',
        ),
        if (trend.months.isEmpty)
          const Text('No trend data available. Refresh Reports.'),
        if (trend.average != null)
          Text(
            'Average recorded spending: ${amount(trend.average!)} across ${trend.ended.length} ended months (including months with no entries).',
          ),
        if (trend.average == null && trend.months.isNotEmpty)
          const Text('No ended months available for an average.'),
        for (final month in trend.months)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${month['month']} · ${amount(month['expense'] as int)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  month['status'] == 'in_progress'
                      ? 'Month in progress · partial totals'
                      : month['status'] == 'future'
                      ? 'Future month · may include planned entries'
                      : 'Month ended · recorded activity only',
                ),
                Text(
                  '${month['record_count']} entries across ${month['recorded_days']} days',
                ),
              ],
            ),
          ),
        if (trend.categories.isNotEmpty) ...[
          const Divider(),
          Text(
            'Categories · ${trend.months.first['month']} to ${trend.months.last['month']}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text(
            'Change compares the last month with the first month, including partial or future months.',
          ),
          for (final id in trend.categories)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.categoryName(id),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text('Total: ${amount(trend.total(id))}'),
                  Text(
                    '${amount(trend.category(trend.months.first, id))} → ${amount(trend.category(trend.months.last, id))}',
                  ),
                  Text(
                    trend.change(id) == 0
                        ? 'No change in recorded spending'
                        : '${amount(trend.change(id).abs())} ${trend.change(id) > 0 ? 'increase' : 'decrease'}',
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
