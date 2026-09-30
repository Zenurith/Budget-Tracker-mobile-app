import 'package:flutter/material.dart';
import '../core/model/contracts.dart';
import '../models/finance.dart';

class TransactionFilters extends StatefulWidget {
  final EntryFilter filter;
  final String currency;
  const TransactionFilters({
    super.key,
    required this.filter,
    required this.currency,
  });
  @override
  State<TransactionFilters> createState() => _TransactionFiltersState();
}

class _TransactionFiltersState extends State<TransactionFilters> {
  final form = GlobalKey<FormState>();
  late DateTime start = widget.filter.start, end = widget.filter.end;
  late final minimum = TextEditingController(
    text: amountText(widget.filter.minAmount),
  );
  late final maximum = TextEditingController(
    text: amountText(widget.filter.maxAmount),
  );
  String amountText(int? amount) =>
      amount == null ? '' : (amount / 100).toStringAsFixed(2);
  int? parse(String value) => RegExp(r'^0(?:\.0{1,2})?$').hasMatch(value.trim())
      ? 0
      : minorUnits(value);
  String? validate(String? value) =>
      value == null || value.trim().isEmpty || parse(value) != null
      ? null
      : 'Use a nonnegative amount with up to 2 decimals';
  String? error;
  @override
  void dispose() {
    minimum.dispose();
    maximum.dispose();
    super.dispose();
  }

  Future<void> pickDates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200, 12, 31),
      initialDateRange: DateTimeRange(start: start, end: end),
    );
    if (range != null && mounted) {
      setState(() {
        start = range.start;
        end = range.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Date and amount filters'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: pickDates,
              icon: const Icon(Icons.date_range),
              label: Text('${dateOf(start)} – ${dateOf(end)}'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: minimum,
              validator: validate,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Minimum (${widget.currency})',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: maximum,
              validator: validate,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Maximum (${widget.currency})',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Leave an amount blank for no limit. Both dates are included.',
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          final min = parse(minimum.text), max = parse(maximum.text);
          if (min != null && max != null && min > max) {
            setState(() => error = 'Minimum must not exceed maximum.');
            return;
          }
          Navigator.pop(
            context,
            EntryFilter(
              start: start,
              end: end,
              minAmount: min,
              maxAmount: max,
              query: widget.filter.query,
              type: widget.filter.type,
              categoryId: widget.filter.categoryId,
            ),
          );
        },
        child: const Text('Apply filters'),
      ),
    ],
  );
}
