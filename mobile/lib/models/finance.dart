import 'package:intl/intl.dart';

typedef Json = Map<String, dynamic>;
String periodOf(DateTime date) => DateFormat('yyyy-MM').format(date);
String dateOf(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
String money(num amount, String currency) => NumberFormat.currency(
  name: currency,
  symbol: currency == 'MYR' ? 'RM ' : '$currency ',
  decimalDigits: 2,
).format(amount / 100);
int? minorUnits(String input) {
  final text = input.trim();
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  final value = int.tryParse(parts[0]);
  if (value == null || value > 1000000000) return null;
  final total =
      value * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  return total > 0 && total <= 100000000000 ? total : null;
}

class FinanceCategory {
  final String id, name, type, icon;
  final String colorHex;
  final bool custom;
  FinanceCategory.fromJson(Json j)
    : id = j['id'],
      name = j['name'],
      type = j['type'],
      icon = j['icon'],
      colorHex = j['color'],
      custom = j['user_id'] != null;
}

class Entry {
  final String? commitmentOccurrenceId;
  final String id, type, categoryId, note, paymentMethod, source;
  final int amount;
  final DateTime date;
  Entry.fromJson(Json j)
    : commitmentOccurrenceId = j['commitment_occurrence_id'],
      id = j['id'] ?? '',
      type = j['type'],
      categoryId = j['category_id'],
      note = j['note'] ?? '',
      paymentMethod = j['payment_method'] ?? 'Cash',
      source = j['source'] ?? 'manual',
      amount = j['amount'],
      date = DateTime.parse(j['date']);
}
