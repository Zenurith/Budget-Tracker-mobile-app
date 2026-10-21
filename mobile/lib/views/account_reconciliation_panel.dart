import 'package:flutter/material.dart';
import '../models/finance.dart';

class AccountReconciliationPanel extends StatelessWidget {
  final Json account, data;
  final int? actual;
  final String currency;
  const AccountReconciliationPanel({
    super.key,
    required this.account,
    required this.data,
    required this.actual,
    required this.currency,
  });
  @override
  Widget build(BuildContext context) {
    final recorded = account['balance'] as int;
    final difference = actual == null ? null : actual! - recorded;
    final review = account['review'] as Map?;
    final activity = (review?['activity'] as List? ?? []).cast<Map>();
    final unassigned = (data['unassigned_review'] as List? ?? []).cast<Map>();
    final candidates = difference == null || difference == 0
        ? <Map>[]
        : [
            for (final e in unassigned)
              if (e['amount'] == difference &&
                  (e['date'] as String).compareTo(
                        account['opening_date'] as String,
                      ) >=
                      0)
                e,
          ];
    final seen = <String>{};
    final duplicates = <Map>[];
    for (final e in activity) {
      final key = '${e['date']}|${e['kind']}|${e['amount']}|${e['note']}';
      if (!seen.add(key)) duplicates.add(e);
    }
    Widget entry(Map e) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        '${e['date']} · ${e['kind']} · ${money(e['amount'], currency)}\n${e['note'] ?? ''}',
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Review ${account['name']} through ${data['as_of']}'),
        Text('Recorded balance: ${money(recorded, currency)}'),
        if (difference != null) ...[
          Text(
            'Difference: ${money(difference, currency)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            difference == 0
                ? 'Balances match.'
                : difference < 0
                ? 'Actual cash is lower. Check for missing expenses or outgoing transfers, or duplicated income.'
                : 'Actual cash is higher. Check for missing income or incoming transfers, or duplicated expenses.',
          ),
        ],
        if (review != null)
          Text(
            'Opening ${money(account['opening_amount'], currency)} + income ${money(review['income'], currency)} − expenses ${money(review['expenses'], currency)} + transfers in ${money(review['transfers_in'], currency)} − transfers out ${money(review['transfers_out'], currency)}',
          ),
        if (candidates.isNotEmpty)
          ExpansionTile(
            title: Text('${candidates.length} unassigned amount matches'),
            children: [
              const Text(
                'These signed amounts match the difference and fall on or after the opening date. Verify the account before assigning them in Transactions.',
              ),
              ...candidates.map(entry),
            ],
          ),
        if (duplicates.isNotEmpty)
          ExpansionTile(
            title: Text('${duplicates.length} possible duplicate entries'),
            children: [
              const Text(
                'Same date, type, amount and note within the recent entries. Repeated payments can be legitimate; inspect the originals before changing anything.',
              ),
              ...duplicates.map(entry),
            ],
          ),
        if (review != null)
          ExpansionTile(
            title: Text(
              'Recent activity (${activity.length} of ${review['activity_count']})',
            ),
            children: activity.map(entry).toList(),
          ),
        ExpansionTile(
          title: Text(
            'Recent unassigned transactions (${unassigned.length} shown)',
          ),
          children: [
            const Text(
              'At most 30 entries through today. A missing match does not rule out older entries or several smaller differences.',
            ),
            ...unassigned.map(entry),
          ],
        ),
        const Text(
          'Compare with your statement. Correct transactions in Transactions; correct transfers by recording the opposite transfer, then the correct transfer. Refresh and check again afterward. Saving this check records the difference only—it does not adjust balances or Protected Funding.',
        ),
      ],
    );
  }
}
