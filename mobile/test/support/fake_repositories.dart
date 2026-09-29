import 'dart:async';
import 'package:pocketwise/core/model/contracts.dart';
import 'package:pocketwise/core/presentation/app_presenters.dart';
import 'package:pocketwise/models/finance.dart';

const testAccount = Account(
  id: 'alex',
  name: 'Alex',
  email: 'alex@example.com',
  currency: 'MYR',
);
final food = FinanceCategory.fromJson({
  'id': 'food',
  'name': 'Food',
  'type': 'expense',
  'icon': 'restaurant',
  'color': '#E3A25F',
});

class FakeRepositories
    implements
        AuthRepository,
        OverviewRepository,
        TransactionRepository,
        BudgetRepository,
        CategoryRepository {
  Account? account;
  AuthInput? lastAuthInput;
  MonthlySnapshot snapshot = MonthlySnapshot(categories: [food]);
  final saves = <EntryDraft>[];
  int authCalls = 0, parses = 0, loads = 0, deletions = 0;
  String? failure;
  Completer<void>? saveGate;
  Future<MonthlySnapshot> Function(DateTime)? onLoad;
  void check() {
    if (failure != null) throw StateError(failure!);
  }

  @override
  Future<Account?> restore() async {
    check();
    return account;
  }

  @override
  Future<Account> authenticate(AuthInput input) async {
    authCalls++;
    lastAuthInput = input;
    check();
    return account = testAccount;
  }

  @override
  Future<void> logout() async {
    check();
    account = null;
  }

  @override
  Future<void> deleteAccount() async {
    check();
    account = null;
  }

  @override
  Future<MonthlySnapshot> loadMonth(DateTime month) async {
    loads++;
    check();
    return onLoad == null ? snapshot : await onLoad!(month);
  }

  @override
  Future<ParsedEntry> parse(String text, DateTime referenceDate) async {
    parses++;
    check();
    return ParsedEntry(
      Entry.fromJson({
        'id': '',
        'amount': 1550,
        'type': 'expense',
        'category_id': 'food',
        'date': '2026-09-27',
        'note': 'Lunch',
        'source': 'nlp',
      }),
      [],
    );
  }

  @override
  Future<void> saveEntry(EntryDraft draft, {String? id}) async {
    saves.add(draft);
    if (saveGate != null) await saveGate!.future;
    check();
  }

  @override
  Future<void> deleteEntry(String id) async {
    check();
    deletions++;
  }

  @override
  Future<void> saveBudget(BudgetDraft draft) async {
    check();
  }

  @override
  Future<void> deleteBudget(String id) async {
    check();
    deletions++;
  }

  @override
  Future<void> saveCategory(CategoryDraft draft, {String? id}) async {
    check();
  }

  @override
  Future<void> deleteCategory(String id) async {
    check();
    deletions++;
  }
}

AppPresenters testPresenters(FakeRepositories repository) => AppPresenters(
  authRepository: repository,
  overviewRepository: repository,
  transactionRepository: repository,
  budgetRepository: repository,
  categoryRepository: repository,
  now: () => DateTime(2026, 9),
);
