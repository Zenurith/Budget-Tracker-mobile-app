import 'dart:async';
import 'package:pocketwise/core/model/contracts.dart';
import 'package:pocketwise/core/presentation/app_presenters.dart';
import 'package:pocketwise/models/finance.dart';
import 'package:pocketwise/features/planning/model/planning_repository.dart';

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

  int profileUpdates = 0, exports = 0;
  Completer<Account>? profileGate;
  Completer<Json>? exportGate;
  @override
  Future<Account> updateProfile(String name) async {
    profileUpdates++;
    check();
    if (profileGate != null) return account = await profileGate!.future;
    final current = account!;
    return account = Account(
      id: current.id,
      name: name,
      email: current.email,
      currency: current.currency,
    );
  }

  @override
  Future<Json> exportData() async {
    exports++;
    check();
    if (exportGate != null) return exportGate!.future;
    return {
      'schema_version': 1,
      'account': {'name': account!.name},
      'transactions': [],
    };
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

  EntryFilter? lastFilter;
  Future<EntryPage> Function(EntryFilter, int)? onSearch;
  @override
  Future<EntryPage> searchEntries(EntryFilter filter, int page) async {
    check();
    lastFilter = filter;
    if (onSearch != null) return onSearch!(filter, page);
    return EntryPage(snapshot.entries, snapshot.entries.length);
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
    savedCategory = draft;
  }

  CategoryDraft? savedCategory;

  @override
  Future<void> deleteCategory(String id) async {
    check();
    deletions++;
  }
}

AppPresenters testPresenters(
  FakeRepositories repository, {
  ExportDestination? exportDestination,
  PlanningRepository? planningRepository,
}) => AppPresenters(
  authRepository: repository,
  overviewRepository: repository,
  transactionRepository: repository,
  budgetRepository: repository,
  categoryRepository: repository,
  planningRepository: planningRepository ?? FakePlanningRepository(),
  exportDestination: exportDestination,
  now: () => DateTime(2026, 9),
);

class FakePlanningRepository implements PlanningRepository {
  @override
  Future<List<Entry>> expenses(DateTime month) async => [];
  Json data = {
    'revision': 0,
    'profile': null,
    'debts': [],
    'commitments': [],
    'occurrences': [],
    'missing_inputs': ['Review your profile.'],
  };
  String? failure;
  Json? savedProfile, savedSchedule, lastPayment;
  int payments = 0;
  Completer<Json>? loadGate;
  Completer<void>? paymentGate;
  @override
  Future<Json> load(DateTime month) async {
    if (failure != null) throw StateError(failure!);
    return loadGate == null ? data : await loadGate!.future;
  }

  @override
  Future<void> saveProfile(Json draft) async {
    savedProfile = draft;
  }

  @override
  Future<void> saveSchedule(String kind, Json draft, {String? id}) async {
    savedSchedule = draft;
  }

  @override
  Future<void> deleteSchedule(String kind, String id, int revision) async {}
  @override
  Future<void> pay(String occurrenceId, Json payment) async {
    payments++;
    lastPayment = payment;
    if (paymentGate != null) await paymentGate!.future;
    if (failure != null) throw StateError(failure!);
  }

  @override
  Future<void> unlink(
    String occurrenceId,
    String transactionId,
    int revision,
  ) async {}
}
