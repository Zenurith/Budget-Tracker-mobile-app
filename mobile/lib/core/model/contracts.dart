import '../../models/finance.dart';

// Deeply immutable snapshots keep one screen from mutating another's state.
Object? freezeValue(Object? value) => switch (value) {
  Map<String, dynamic> map => freezeJson(map),
  List list => List<Object?>.unmodifiable(list.map(freezeValue)),
  _ => value,
};
Json freezeJson(Json value) => Map<String, dynamic>.unmodifiable(
  value.map((key, value) => MapEntry(key, freezeValue(value))),
);

class Account {
  final String id, name, email, currency;
  const Account({
    required this.id,
    required this.name,
    required this.email,
    required this.currency,
  });
  factory Account.fromJson(Json json) => Account(
    id: json['id'] ?? '',
    name: json['name'],
    email: json['email'],
    currency: json['currency'],
  );
}

class AuthInput {
  final String mode, email, password, name;
  final String? currency;
  const AuthInput({
    required this.mode,
    this.email = '',
    this.password = '',
    this.name = '',
    this.currency,
  });
}

class MonthlySnapshot {
  final Json summary;
  final List<FinanceCategory> categories;
  final List<Entry> entries;
  final List<Json> budgets;
  MonthlySnapshot({
    Json summary = const {},
    List<FinanceCategory> categories = const [],
    List<Entry> entries = const [],
    List<Json> budgets = const [],
  }) : summary = freezeJson(summary),
       categories = List.unmodifiable(categories),
       entries = List.unmodifiable(entries),
       budgets = List.unmodifiable(budgets.map(freezeJson));
}

class EntryDraft {
  final int amount;
  final String type, categoryId, note, paymentMethod, source;
  final DateTime date;
  const EntryDraft({
    required this.amount,
    required this.type,
    required this.categoryId,
    required this.date,
    this.note = '',
    this.paymentMethod = 'Cash',
    this.source = 'manual',
  });
}

class ParsedEntry {
  final Entry entry;
  final List<String> warnings;
  ParsedEntry(this.entry, List<String> warnings)
    : warnings = List.unmodifiable(warnings);
}

class BudgetDraft {
  final String period;
  final String? categoryId;
  final int limitAmount, alertThreshold;
  const BudgetDraft({
    required this.period,
    this.categoryId,
    required this.limitAmount,
    required this.alertThreshold,
  });
}

class CategoryDraft {
  final String name, type, icon, color;
  const CategoryDraft({
    required this.name,
    required this.type,
    this.icon = 'category',
    this.color = '#4D8B70',
  });
}

abstract interface class AuthRepository {
  Future<Account?> restore();
  Future<Account> authenticate(AuthInput input);
  Future<void> logout();
  Future<void> deleteAccount();
}

abstract interface class OverviewRepository {
  Future<MonthlySnapshot> loadMonth(DateTime month);
}

abstract interface class TransactionRepository {
  Future<ParsedEntry> parse(String text, DateTime referenceDate);
  Future<void> saveEntry(EntryDraft draft, {String? id});
  Future<void> deleteEntry(String id);
}

abstract interface class BudgetRepository {
  Future<void> saveBudget(BudgetDraft draft);
  Future<void> deleteBudget(String id);
}

abstract interface class CategoryRepository {
  Future<void> saveCategory(CategoryDraft draft, {String? id});
  Future<void> deleteCategory(String id);
}

class InputRules {
  static String? name(String? value) =>
      value == null || value.trim().isEmpty ? 'Enter a name' : null;
  static String? email(String? value) =>
      value == null ||
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
      ? 'Enter a valid email'
      : null;
  static String? password(String? value, {required bool register}) =>
      value == null || value.length < (register ? 8 : 1)
      ? (register ? 'Use at least 8 characters' : 'Enter your password')
      : null;
  static String? amount(String? value) => minorUnits(value ?? '') == null
      ? 'Enter a positive amount with up to 2 decimals'
      : null;
  static String? threshold(String? value) {
    final n = int.tryParse(value ?? '');
    return n == null || n < 1 || n > 100 ? 'Choose 1–100' : null;
  }

  static const currencies = ['EUR', 'GBP', 'MYR', 'SGD', 'USD'];
}
