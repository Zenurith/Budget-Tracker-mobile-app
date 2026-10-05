import 'package:flutter/material.dart';
import '../core/view/presenter_builder.dart';
import '../features/funding/presenter/funding_presenter.dart';
import '../features/planning/model/input_rules.dart';
import '../models/finance.dart';
import 'funding_screen.dart';

class WishlistScreen extends StatefulWidget {
  final FundingPresenter presenter;
  const WishlistScreen({super.key, required this.presenter});
  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  FundingPresenter get p => widget.presenter;
  @override
  void initState() {
    super.initState();
    p.reload();
  }

  Future<void> editor(String mode, {Json? item}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          [
            'snapshot',
            'plan',
            'allocate',
            'release',
            'reallocate',
          ].contains(mode)
          ? FundingEditor(presenter: p, mode: mode, goal: item)
          : WishlistEditor(presenter: p, mode: mode, item: item),
    );
    if (mounted) await p.reload();
  }

  Future<void> remove(Json item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${item['name']}?'),
        content: const Text(
          'Release reserved cash first. Items with purchase history must be archived instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete item'),
          ),
        ],
      ),
    );
    if (yes == true) await p.deleteWishlist(item['id']);
  }

  @override
  Widget build(BuildContext context) => PresenterBuilder(
    presenter: p,
    builder: (context, state) {
      final data = state.data;
      final currency = data['currency'] as String? ?? '';
      final items = (data['wishlist'] as List? ?? []).cast<Json>();
      String amount(dynamic n) =>
          n is int ? money(n, currency) : 'Needs confirmation';
      Widget action(
        String label,
        String mode, {
        Json? item,
        bool enabled = true,
      }) => TextButton(
        onPressed: state.editable && enabled
            ? () => editor(mode, item: item)
            : null,
        child: Text(label),
      );
      return Scaffold(
        appBar: AppBar(
          title: const Text('Guilt-free wishlist'),
          actions: [
            IconButton(
              tooltip: 'Refresh wishlist',
              onPressed: state.saving ? null : p.reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Save for wanted purchases using cash already reserved. Forecasts do not fund items. This app records purchases; it does not make payments.',
            ),
            if (state.busy || state.saving) const LinearProgressIndicator(),
            if (state.stale)
              const Text(
                'Activity changed. Refresh and review before continuing.',
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
              Text('Unallocated cash: ${amount(data['free_to_allocate'])}'),
              Text(
                'Wishlist reserved: ${amount(data['wishlist_reserved'])} · Coverage shortfall: ${amount(data['coverage_shortfall'])}',
              ),
              Text('Horizon: ${data['as_of']} through ${data['horizon_end']}'),
              if (data['snapshot'] != null)
                Text('Cash as of ${data['snapshot']['as_of']}'),
              for (final reason in [
                ...data['missing_inputs'] as List? ?? [],
                ...data['stale_reasons'] as List? ?? [],
              ])
                Text('• $reason'),
              Wrap(
                spacing: 8,
                children: [
                  action('Add wishlist item', 'item'),
                  action('Reconcile cash', 'snapshot'),
                  action('Review funding plan', 'plan'),
                ],
              ),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Your wishlist is empty. Add something you want to save for.',
                  ),
                ),
              for (final item in items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['name'],
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          '${item['status']} · priority ${item['priority']}',
                        ),
                        Text(
                          'Total cost ${amount(item['target_cost'])} · Reserved ${amount(item['funded_amount'])}',
                        ),
                        Text(
                          'Still to save: ${amount(item['remaining_target'])}',
                        ),
                        Text(
                          state.stale
                              ? 'Needs updated information'
                              : item['readiness'] as String? ??
                                    'Refresh to review readiness',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        for (final reason in item['reasons'] as List? ?? [])
                          Text('• $reason'),
                        if (item['forecast_date'] != null && !state.stale)
                          Text(
                            'Projected ${item['forecast_date']} if you save ${amount(item['monthly_contribution'])} monthly (${item['months_needed']} contributions). Future income is not available cash.',
                          )
                        else if (item['forecast_reason'] != null)
                          Text(item['forecast_reason']),
                        if (item['target_date'] != null)
                          Text('Your target date: ${item['target_date']}'),
                        if ((item['notes'] as String? ?? '').isNotEmpty)
                          Text(item['notes']),
                        if (item['reference_url'] != null)
                          SelectableText(item['reference_url']),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (item['has_purchase'] == true)
                              action('Archive item', 'item', item: item),
                            if (item['status'] != 'purchased' &&
                                item['has_purchase'] != true) ...[
                              action('Edit item', 'item', item: item),
                              action(
                                'Reserve cash',
                                'allocate',
                                item: item,
                                enabled:
                                    data['can_allocate'] == true &&
                                    item['status'] == 'active',
                              ),
                              action(
                                'Record actual purchase',
                                'purchase',
                                item: item,
                              ),
                              TextButton(
                                onPressed: state.editable
                                    ? () => remove(item)
                                    : null,
                                child: const Text('Delete'),
                              ),
                            ],
                            if ((item['funded_amount'] as int? ?? 0) > 0) ...[
                              action('Release cash', 'release', item: item),
                              action(
                                'Move reservation',
                                'reallocate',
                                item: item,
                                enabled: data['usable'] == true,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if ((data['purchases'] as List? ?? []).isNotEmpty)
                Text(
                  'Purchase history',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              for (final purchase in data['purchases'] as List? ?? [])
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${items.where((i) => i['id'] == purchase['item_id']).firstOrNull?['name'] ?? 'Purchase'} · ${amount(purchase['amount'])} · ${purchase['date']}',
                        ),
                        Text(
                          '${purchase['status']} · ${purchase['readiness'] == 'ready_under_plan' ? 'Ready under the reviewed plan when recorded' : 'Pre-purchase readiness was not assessed'}',
                        ),
                        Text(
                          'Refunds recorded: ${amount((purchase['refunds'] as List).fold<int>(0, (sum, r) => sum + (r['amount'] as int)))}',
                        ),
                        if (purchase['status'] == 'recorded')
                          Wrap(
                            spacing: 8,
                            children: [
                              action(
                                'Record refund',
                                'refund',
                                item: Map<String, dynamic>.from(purchase),
                              ),
                              action(
                                'Correct purchase link',
                                'reverse',
                                item: Map<String, dynamic>.from(purchase),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}

class WishlistEditor extends StatefulWidget {
  final FundingPresenter presenter;
  final String mode;
  final Json? item;
  const WishlistEditor({
    super.key,
    required this.presenter,
    required this.mode,
    this.item,
  });
  @override
  State<WishlistEditor> createState() => _WishlistEditorState();
}

class _WishlistEditorState extends State<WishlistEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  late final Json data;
  String status = 'active', baseline = 'subtract_from_prior_snapshot';
  String? category, account, transactionId, error;
  bool busy = false, confirmed = false, existing = false;
  List<Json> candidates = [];
  FundingPresenter get p => widget.presenter;
  bool get editing => widget.mode == 'item';
  bool get buying => widget.mode == 'purchase';
  bool get refunding => widget.mode == 'refund';
  String get currency => data['currency'] as String? ?? '';
  @override
  void initState() {
    super.initState();
    data = p.state.data;
    final item = widget.item ?? {};
    status = item['status'] == 'purchased'
        ? 'archived'
        : item['status'] as String? ?? 'active';
    for (final key in [
      'name',
      'target_cost',
      'priority',
      'target_date',
      'notes',
      'reference_url',
      'monthly_contribution',
      'next_contribution_date',
      'amount',
      'date',
      'reason',
    ]) {
      dynamic value = item[key];
      if (['target_cost', 'monthly_contribution'].contains(key) &&
          value is int) {
        value = (value / 100).toStringAsFixed(2);
      }
      if (key == 'amount') {
        value = buying
            ? ((item['target_cost'] as int) / 100).toStringAsFixed(2)
            : '';
      }
      if (key == 'date') value = data['as_of'];
      if (key == 'priority' || key == 'monthly_contribution') value ??= '0';
      fields[key] = TextEditingController(text: value?.toString() ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String text(String key) => fields[key]!.text.trim();
  String? optional(String key) => text(key).isEmpty ? null : text(key);
  Widget field(
    String key,
    String label, {
    bool monetary = false,
    bool date = false,
    bool optional = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: fields[key],
      enabled: !busy,
      decoration: InputDecoration(labelText: label),
      keyboardType: monetary
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      onChanged: buying && (key == 'date' || key == 'amount')
          ? (_) => setState(() {
              candidates = [];
              transactionId = null;
              confirmed = false;
            })
          : null,
      validator: (v) {
        if (monetary) return PlanningInputRules.money(v, optional: optional);
        if (date) return PlanningInputRules.date(v, optional: optional);
        if (key == 'priority') {
          final n = int.tryParse(v ?? '');
          return n == null || n < 0 || n > 100
              ? 'Use a whole number from 0 to 100'
              : null;
        }
        return !optional && (v ?? '').trim().isEmpty ? 'Required' : null;
      },
    ),
  );
  Future<void> findExpenses() async {
    if (PlanningInputRules.date(text('date')) != null ||
        minorUnits(text('amount')) == null) {
      setState(() => error = 'Enter a valid date and positive amount first.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final items = await p.purchaseExpenses(
        text('date'),
        minorUnits(text('amount'))!,
      );
      if (mounted) {
        setState(() {
          candidates = items;
          transactionId = null;
          if (items.isEmpty) {
            error = 'No unlinked expenses match this date and amount.';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(
        editing
            ? 'Wishlist item'
            : buying
            ? 'Record actual purchase'
            : refunding
            ? 'Record actual refund'
            : 'Correct purchase link',
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (editing) ...[
                  field('name', 'Item name'),
                  field(
                    'target_cost',
                    'Total cost ($currency), including tax and shipping',
                    monetary: true,
                  ),
                  field('priority', 'Priority (0–100, higher first)'),
                  field(
                    'target_date',
                    'Your target date (optional)',
                    date: true,
                    optional: true,
                  ),
                  field('notes', 'Notes (optional)', optional: true),
                  field(
                    'reference_url',
                    'Reference URL (optional)',
                    optional: true,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Item status'),
                    items: [
                      for (final s in ['active', 'paused', 'archived'])
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            status = v!;
                            confirmed = false;
                          }),
                  ),
                  const SizedBox(height: 14),
                  field(
                    'monthly_contribution',
                    'Planned monthly contribution ($currency)',
                    monetary: true,
                  ),
                  field(
                    'next_contribution_date',
                    'Next planned contribution (optional)',
                    date: true,
                    optional: true,
                  ),
                  const Text(
                    'Contributions are forecasts only. To pause or archive, explicitly set the monthly contribution to 0. Reserved cash stays with the item until you release or move it.',
                  ),
                ],
                if (buying) ...[
                  Text(
                    '${widget.item!['name']} · reserved ${money(widget.item!['funded_amount'], currency)}',
                  ),
                  const Text(
                    'Record a purchase that actually happened. For unplanned spending, record the expense normally, reconcile cash, then link it here.',
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: baseline,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Cash treatment',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'subtract_from_prior_snapshot',
                        child: Text('Deduct from prior cash'),
                      ),
                      DropdownMenuItem(
                        value: 'already_reconciled',
                        child: Text('Already included in cash'),
                      ),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            baseline = v!;
                            confirmed = false;
                            existing = false;
                            transactionId = null;
                          }),
                  ),
                  const SizedBox(height: 14),
                  if (baseline == 'subtract_from_prior_snapshot') ...[
                    const Text(
                      'The reviewed balance must exclude this payment. This purchase must be the only cash activity since that review. Use this path for cash/debit payments from an included account.',
                    ),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Account used',
                      ),
                      items: [
                        for (final a
                            in data['snapshot']?['accounts'] as List? ?? [])
                          DropdownMenuItem(
                            value: a['name'] as String,
                            child: Text(
                              '${a['name']} · ${money(a['amount'], currency)}',
                            ),
                          ),
                      ],
                      onChanged: busy ? null : (v) => account = v,
                      validator: (v) =>
                          v == null ? 'Choose the account used' : null,
                    ),
                  ] else ...[
                    const Text(
                      'Reconcile cash including this payment before opening this form. It will not be deducted again. Pre-purchase readiness is not assessed.',
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Link an existing expense'),
                      value: existing,
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              existing = v;
                              transactionId = null;
                              confirmed = false;
                            }),
                    ),
                    if (!existing)
                      const Text(
                        'This creates the missing expense. Confirm you have not already recorded it.',
                      ),
                  ],
                ],
                if (buying || refunding) ...[
                  field('amount', 'Actual amount ($currency)', monetary: true),
                  field('date', 'Actual date (YYYY-MM-DD)', date: true),
                  if (buying && existing) ...[
                    OutlinedButton(
                      onPressed: busy ? null : findExpenses,
                      child: const Text('Find matching expenses'),
                    ),
                    if (candidates.isNotEmpty)
                      DropdownButtonFormField<String>(
                        key: ValueKey(candidates),
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Existing expense',
                        ),
                        items: [
                          for (final e in candidates)
                            DropdownMenuItem(
                              value: e['id'] as String,
                              child: Text(
                                '${e['date']} · ${e['note']} · ${money(e['amount'], currency)}',
                              ),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (v) => setState(() {
                                transactionId = v;
                                category = candidates.firstWhere(
                                  (e) => e['id'] == v,
                                )['category_id'];
                              }),
                        validator: (v) =>
                            v == null ? 'Choose an expense' : null,
                      ),
                  ] else
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: [
                        for (final c in data['categories'] as List? ?? [])
                          if (c['type'] == (refunding ? 'income' : 'expense'))
                            DropdownMenuItem(
                              value: c['id'] as String,
                              child: Text(c['name']),
                            ),
                      ],
                      onChanged: busy ? null : (v) => category = v,
                      validator: (v) => v == null ? 'Choose a category' : null,
                    ),
                ],
                if (!buying && !editing) ...[
                  field('reason', 'Reason'),
                  Text(
                    refunding
                        ? 'This records a separate income entry. Reconcile actual balances afterward; returned cash is not automatically reserved again.'
                        : 'This removes the link and reopens the item without restoring its reservation. The original expense and refunds remain in your tracker. Correct those entries if needed, then reconcile cash. This does not record a refund.',
                  ),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: confirmed,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => confirmed = v!),
                  title: Text(
                    editing
                        ? 'I reviewed the total cost and forecast; paused funds remain reserved'
                        : buying
                        ? baseline == 'already_reconciled'
                              ? 'I confirm this purchase happened, is included in the reconciled balance, and this expense is not duplicated'
                              : 'I confirm this purchase happened and is the only payment missing from the reviewed cash balance'
                        : refunding
                        ? 'I confirm this refund was received'
                        : 'I confirm this link correction and will reconcile balances',
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
          onPressed: busy || !confirmed ? null : save,
          child: Text(busy ? 'Saving…' : 'Confirm'),
        ),
      ],
    ),
  );
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (buying && existing && transactionId == null) {
      setState(() => error = 'Find and select the existing expense.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    bool ok;
    if (editing) {
      ok = await p.saveWishlist({
        'name': text('name'),
        'target_cost': PlanningInputRules.amount(text('target_cost')),
        'priority': int.parse(text('priority')),
        'target_date': optional('target_date'),
        'notes': text('notes'),
        'reference_url': optional('reference_url'),
        'status': status,
        'monthly_contribution': PlanningInputRules.amount(
          text('monthly_contribution'),
        ),
        'next_contribution_date': optional('next_contribution_date'),
      }, id: widget.item?['id']);
    } else if (buying) {
      ok = await p.recordPurchase(widget.item!['id'], {
        'amount': PlanningInputRules.amount(text('amount')),
        'date': text('date'),
        'category_id': category,
        'confirmed': true,
        'baseline_effect': baseline,
        if (baseline == 'subtract_from_prior_snapshot') ...{
          'quote': widget.item!['quote'],
          'account_name': account,
        },
        if (baseline == 'already_reconciled') ...{
          'snapshot_token': data['snapshot_token'],
          if (existing) 'transaction_id': transactionId,
        },
      });
    } else {
      ok = await p.adjustPurchase(widget.item!['id'], widget.mode, {
        'confirmed': true,
        'reason': text('reason'),
        if (refunding) ...{
          'amount': PlanningInputRules.amount(text('amount')),
          'date': text('date'),
          'category_id': category,
        },
      });
    }
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        busy = false;
        error = p.state.error ?? 'Refresh and review before trying again.';
      });
    }
  }
}
