import '../../../models/finance.dart';

class TransactionInputRules {
  static String? amount(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter an amount';
    if (RegExp(r'^-\d+(\.\d{1,2})?$').hasMatch(text) ||
        RegExp(r'^0+(\.0{1,2})?$').hasMatch(text)) {
      return 'Enter an amount greater than zero';
    }
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) {
      return 'Use numbers and up to 2 decimal places (for example, 15.50)';
    }
    if (minorUnits(text) == null) {
      return 'Amount must be 1,000,000,000.00 or less';
    }
    return null;
  }

  static String? note(String? value) => (value ?? '').trim().runes.length > 500
      ? 'Keep the note within 500 characters'
      : null;
}
