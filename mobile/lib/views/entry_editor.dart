import '../features/transactions/model/transaction_input_rules.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/presentation/app_presenters.dart';
import '../core/model/contracts.dart';
import '../core/view/presenter_builder.dart';
import '../models/finance.dart';

Future<void> showEntryEditor(
  BuildContext context,
  AppPresenters presenters, {
  Entry? entry,
  bool natural = false,
  bool duplicate = false,
}) => showDialog(
  context: context,
  builder: (_) => EntryEditor(
    presenters: presenters,
    entry: entry,
    natural: natural,
    duplicate: duplicate,
  ),
);

class EntryEditor extends StatefulWidget {
  final AppPresenters presenters;
  final Entry? entry;
  final bool natural, duplicate;
  const EntryEditor({
    super.key,
    required this.presenters,
    this.entry,
    this.natural = false,
    this.duplicate = false,
  });
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController(),
      note = TextEditingController(),
      natural = TextEditingController();
  late String type, categoryId, payment, source;
  late DateTime date;
  String? accountId;
  bool parsed = false;
  bool get busy => widget.presenters.transactions.state.busy;
  String? get error => widget.presenters.transactions.state.error;
  List<String> warnings = [];
  final splitRows = <_SplitRow>[];
  String? splitError;
  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    accountId = e?.accountId;
    if (widget.duplicate &&
        (widget.presenters.overview.summary['money_accounts'] as List? ?? [])
            .any((a) => a['id'] == accountId && a['archived'] == true)) {
      accountId = null;
    }
    type = e?.type ?? 'expense';
    categoryId =
        e?.categoryId ??
        widget.presenters.overview.categories
            .firstWhere((c) => c.type == type)
            .id;
    payment = e?.paymentMethod ?? 'Cash';
    source = widget.duplicate ? 'manual' : e?.source ?? 'manual';
    date = widget.duplicate ? DateTime.now() : e?.date ?? DateTime.now();
    amount.text = e == null ? '' : (e.amount / 100).toStringAsFixed(2);
    note.text = e?.note ?? '';
    for (final part in e?.splits ?? <EntrySplit>[]) {
      splitRows.add(
        _SplitRow(part.categoryId, (part.amount / 100).toStringAsFixed(2)),
      );
    }
  }

  @override
  void dispose() {
    for (final row in splitRows) {
      row.amount.dispose();
    }
    amount.dispose();
    note.dispose();
    natural.dispose();
    super.dispose();
  }

  Future<void> parse() async {
    final result = await widget.presenters.transactions.parse(
      natural.text,
      DateTime.now(),
    );
    if (!mounted || result == null) return;
    final e = result.entry;
    setState(() {
      type = e.type;
      categoryId = e.categoryId;
      amount.text = (e.amount / 100).toStringAsFixed(2);
      note.text = e.note;
      date = e.date;
      for (final row in splitRows) {
        row.amount.dispose();
      }
      splitRows.clear();
      splitError = null;
      source = 'nlp';
      parsed = true;
      warnings = result.warnings;
    });
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (splitRows.isNotEmpty &&
        (splitRows.map((r) => r.category).toSet().length != splitRows.length ||
            splitRows.fold<int>(
                  0,
                  (sum, r) => sum + (minorUnits(r.amount.text) ?? 0),
                ) !=
                minorUnits(amount.text))) {
      setState(
        () => splitError =
            'Use distinct categories and make the split amounts equal the total.',
      );
      return;
    }
    final saved = await widget.presenters.transactions.save(
      EntryDraft(
        accountId: accountId,
        expectedVersion: widget.duplicate ? null : widget.entry?.version,
        amount: minorUnits(amount.text)!,
        type: type,
        categoryId: splitRows.isEmpty ? categoryId : splitRows.first.category,
        splits: [
          for (final row in splitRows)
            EntrySplit(
              categoryId: row.category,
              amount: minorUnits(row.amount.text)!,
            ),
        ],
        date: date,
        note: note.text.trim(),
        paymentMethod: payment,
        source: source,
      ),
      id: widget.duplicate ? null : widget.entry?.id,
    );
    if (mounted && saved) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final choices = widget.presenters.overview.categories
        .where((c) => c.type == type)
        .toList();
    final showForm = !widget.natural || parsed;
    return PresenterBuilder(
      presenter: widget.presenters.transactions,
      builder: (context, state) => AlertDialog(
        scrollable: true,
        title: Text(
          widget.duplicate
              ? 'Duplicate transaction'
              : widget.entry != null
              ? 'Edit transaction'
              : widget.natural
              ? 'Just say it naturally'
              : 'A new transaction',
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.duplicate) ...[
                const Text(
                  'Review this new transaction before saving. The date is set to today; bill and wishlist links are not copied.',
                ),
                const SizedBox(height: 16),
              ],
              if (widget.natural) ...[
                const Text(
                  'Try “Spent 15.50 on lunch yesterday”. Your text is processed locally by the app’s server. Review the details before saving.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: natural,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    hintText: 'What’s the story?',
                    labelText: 'Describe a transaction',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : parse,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(parsed ? 'Parse again' : 'Find the details'),
                ),
                if (parsed) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Looking right? Review and confirm below.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ...warnings.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        s,
                        style: const TextStyle(color: Color(0xFF906424)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
              ],
              if (showForm)
                Form(
                  key: form,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'expense',
                            label: Text('Expense'),
                            icon: Icon(Icons.north_east),
                          ),
                          ButtonSegment(
                            value: 'income',
                            label: Text('Income'),
                            icon: Icon(Icons.south_west),
                          ),
                        ],
                        selected: {type},
                        onSelectionChanged: busy || splitRows.isNotEmpty
                            ? null
                            : (v) => setState(() {
                                type = v.first;
                                categoryId = widget
                                    .presenters
                                    .overview
                                    .categories
                                    .firstWhere((c) => c.type == type)
                                    .id;
                              }),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: amount,
                        enabled: !busy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              'Amount (${widget.presenters.overview.currency})',
                          hintText: '0.00',
                        ),
                        validator:
                            widget.presenters.transactions.validateAmount,
                      ),
                      const SizedBox(height: 16),
                      if (splitRows.isEmpty)
                        DropdownButtonFormField<String>(
                          key: ValueKey('$type-$categoryId'),
                          initialValue: choices.any((c) => c.id == categoryId)
                              ? categoryId
                              : null,
                          validator: (value) =>
                              value == null ||
                                  !choices.any((c) => c.id == value)
                              ? 'Choose a category'
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                          ),
                          items: choices
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.name),
                                ),
                              )
                              .toList(),
                          onChanged: busy
                              ? null
                              : (s) => setState(() => categoryId = s!),
                        ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Split across categories'),
                        value: splitRows.isNotEmpty,
                        onChanged: busy
                            ? null
                            : (enabled) => setState(() {
                                splitError = null;
                                for (final row in splitRows) {
                                  row.amount.dispose();
                                }
                                splitRows.clear();
                                if (enabled) {
                                  splitRows.add(
                                    _SplitRow(categoryId, amount.text),
                                  );
                                  splitRows.add(
                                    _SplitRow(
                                      choices
                                              .where((c) => c.id != categoryId)
                                              .firstOrNull
                                              ?.id ??
                                          categoryId,
                                      '',
                                    ),
                                  );
                                }
                              }),
                      ),
                      if (splitRows.isNotEmpty) ...[
                        const Text(
                          'This stays one payment. Split amounts must add up to the total. Turn splitting off to change income/expense type.',
                        ),
                        for (final (index, row) in splitRows.indexed)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              children: [
                                DropdownButtonFormField<String>(
                                  key: ObjectKey(row),
                                  initialValue:
                                      choices.any((c) => c.id == row.category)
                                      ? row.category
                                      : null,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: 'Split ${index + 1} category',
                                  ),
                                  items: [
                                    for (final c in choices)
                                      DropdownMenuItem(
                                        value: c.id,
                                        child: Text(c.name),
                                      ),
                                  ],
                                  validator: (v) =>
                                      v == null ? 'Choose a category' : null,
                                  onChanged: busy
                                      ? null
                                      : (v) =>
                                            setState(() => row.category = v!),
                                ),
                                TextFormField(
                                  controller: row.amount,
                                  enabled: !busy,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    labelText: 'Split ${index + 1} amount',
                                  ),
                                  validator: widget
                                      .presenters
                                      .transactions
                                      .validateAmount,
                                ),
                                if (splitRows.length > 2)
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => setState(() {
                                            splitRows.remove(row);
                                            row.amount.dispose();
                                          }),
                                    child: const Text('Remove split'),
                                  ),
                              ],
                            ),
                          ),
                        TextButton(
                          onPressed: busy || splitRows.length >= 20
                              ? null
                              : () => setState(
                                  () => splitRows.add(
                                    _SplitRow(choices.first.id, ''),
                                  ),
                                ),
                          child: const Text('Add split'),
                        ),
                        if (splitError != null)
                          Text(
                            splitError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                final selected = await showDatePicker(
                                  context: context,
                                  initialDate: date.isBefore(DateTime(2000))
                                      ? DateTime(2000)
                                      : date.isAfter(DateTime(2100))
                                      ? DateTime(2100)
                                      : date,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (selected != null && mounted) {
                                  setState(() => date = selected);
                                }
                              },
                        icon: const Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                        ),
                        label: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(DateFormat.yMMMMd().format(date)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: accountId ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Account'),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Unassigned'),
                          ),
                          for (final a
                              in widget
                                          .presenters
                                          .overview
                                          .summary['money_accounts']
                                      as List? ??
                                  [])
                            DropdownMenuItem(
                              enabled:
                                  a['archived'] != true ||
                                  (!widget.duplicate &&
                                      widget.entry?.accountId == a['id']),
                              value: a['id'] as String,
                              child: Text(
                                '${a['name']}${a['archived'] == true ? ' · Archived' : ''}',
                              ),
                            ),
                          if (accountId != null &&
                              !(widget
                                              .presenters
                                              .overview
                                              .summary['money_accounts']
                                          as List? ??
                                      [])
                                  .any((a) => a['id'] == accountId))
                            DropdownMenuItem(
                              value: accountId,
                              child: const Text(
                                'Assigned account (details unavailable)',
                              ),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (value) => setState(
                                () => accountId = value == '' ? null : value,
                              ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: note,
                        enabled: !busy,
                        validator: TransactionInputRules.note,
                        maxLength: 500,
                        decoration: const InputDecoration(
                          labelText: 'Note',
                          hintText: 'A little context for later',
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: payment,
                        decoration: const InputDecoration(
                          labelText: 'Payment method',
                        ),
                        items:
                            {
                                  'Cash',
                                  'Debit card',
                                  'Credit card',
                                  'Bank transfer',
                                  'E-wallet',
                                  payment,
                                }
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s),
                                  ),
                                )
                                .toList(),
                        onChanged: busy ? null : (s) => payment = s!,
                      ),
                    ],
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (showForm)
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(
                widget.natural ? 'Confirm & save' : 'Save transaction',
              ),
            ),
        ],
      ),
    );
  }
}

class _SplitRow {
  String category;
  final TextEditingController amount;
  _SplitRow(this.category, String value)
    : amount = TextEditingController(text: value);
}
