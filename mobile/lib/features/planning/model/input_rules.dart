import '../../../models/finance.dart';

class PlanningInputRules {
  static int? amount(String input) =>
      RegExp(r'^0(?:\.0{1,2})?$').hasMatch(input.trim())
      ? 0
      : minorUnits(input);
  static String? money(String? value, {bool optional = false}) =>
      optional && (value ?? '').trim().isEmpty
      ? null
      : amount(value ?? '') == null
      ? 'Enter an amount with up to 2 decimals'
      : null;
  static String? date(String? value, {bool optional = false}) {
    if (optional && (value ?? '').trim().isEmpty) return null;
    final parsed = DateTime.tryParse(value ?? '');
    return parsed == null || dateOf(parsed) != value ? 'Use YYYY-MM-DD' : null;
  }
}
