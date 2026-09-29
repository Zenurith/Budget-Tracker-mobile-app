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
}) => showDialog(
  context: context,
  builder: (_) =>
      EntryEditor(presenters: presenters, entry: entry, natural: natural),
);

class EntryEditor extends StatefulWidget {
  final AppPresenters presenters;
  final Entry? entry;
  final bool natural;
  const EntryEditor({
    super.key,
    required this.presenters,
    this.entry,
    this.natural = false,
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
  bool parsed = false;
  bool get busy => widget.presenters.transactions.state.busy;
  String? get error => widget.presenters.transactions.state.error;
  List<String> warnings = [];
  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    type = e?.type ?? 'expense';
    categoryId =
        e?.categoryId ??
        widget.presenters.overview.categories
            .firstWhere((c) => c.type == type)
            .id;
    payment = e?.paymentMethod ?? 'Cash';
    source = e?.source ?? 'manual';
    date = e?.date ?? DateTime.now();
    amount.text = e == null ? '' : (e.amount / 100).toStringAsFixed(2);
    note.text = e?.note ?? '';
  }

  @override
  void dispose() {
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
      source = 'nlp';
      parsed = true;
      warnings = result.warnings;
    });
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final saved = await widget.presenters.transactions.save(
      EntryDraft(
        amount: minorUnits(amount.text)!,
        type: type,
        categoryId: categoryId,
        date: date,
        note: note.text.trim(),
        paymentMethod: payment,
        source: source,
      ),
      id: widget.entry?.id,
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
          widget.entry != null
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
                        onSelectionChanged: busy
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
                      DropdownButtonFormField<String>(
                        key: ValueKey('$type-$categoryId'),
                        initialValue: categoryId,
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
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                final selected = await showDatePicker(
                                  context: context,
                                  initialDate: date,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (selected != null) {
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
                      TextFormField(
                        controller: note,
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
