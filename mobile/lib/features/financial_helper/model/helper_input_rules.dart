import '../../../models/finance.dart';

class HelperInputRules {
  static String? validate(Json assumptions, String effectiveDate) {
    final date = DateTime.tryParse(effectiveDate);
    if (date == null || dateOf(date) != effectiveDate) {
      return 'Use a valid effective date in YYYY-MM-DD format.';
    }
    bool validAmount(dynamic value) =>
        value is int && value >= 0 && value <= 100000000000;
    for (final key in [
      'gross_monthly',
      'net_monthly',
      'additional_debt_monthly',
    ]) {
      if (assumptions[key] != null && !validAmount(assumptions[key])) {
        return 'Use nonnegative amounts with up to two decimal places.';
      }
    }
    final notes = assumptions['notes'] ?? '';
    if (notes is! String || notes.length > 500) {
      return 'Keep assumptions within 500 characters.';
    }
    final debts = assumptions['debt_payments'] ?? [];
    if (debts is! List || debts.length > 100) {
      return 'Review the debt payment changes.';
    }
    final ids = <String>{};
    for (final debt in debts) {
      if (debt is! Map ||
          debt['id'] is! String ||
          (debt['id'] as String).isEmpty ||
          !validAmount(debt['monthly_payment']) ||
          !ids.add(debt['id'] as String)) {
        return 'Enter one nonnegative monthly payment for each changed debt.';
      }
    }
    return null;
  }
}
