import 'dart:async';
import 'package:pocketwise/models/finance.dart';
import 'package:pocketwise/features/records/model/records_repository.dart';
import 'package:pocketwise/features/recovery/model/recovery_repository.dart';

class FakeRecords implements RecordsRepository, CSVSource, RecoveryRepository {
  String? contents = 'csv', failure;
  Completer<Json>? pendingBalances;
  Completer<void>? pendingRecovery;
  Json balancesData = {'opening': null, 'items': [], 'total': 0, 'page': 1};
  Json historyData = {'items': [], 'total': 0, 'page': 1};
  Json preview = {
    'total': 2,
    'currency': 'EUR',
    'items': [
      {
        'row': 1,
        'error': null,
        'duplicate': false,
        'transaction': {
          'date': '2026-10-01',
          'type': 'expense',
          'amount': 1250,
          'note': 'Lunch',
        },
      },
      {
        'row': 2,
        'error': null,
        'duplicate': true,
        'duplicate_reason': 'Matches an existing transaction',
        'transaction': {
          'date': '2026-10-01',
          'type': 'expense',
          'amount': 1250,
          'note': 'Lunch',
        },
      },
    ],
  };
  final imports = <Json>[], openings = <Json>[];
  final undos = <String>[];
  int requests = 0, resets = 0;
  @override
  Future<Json> balances(int page) async =>
      pendingBalances != null ? await pendingBalances!.future : balancesData;
  @override
  Future<Json> history(int page) async => historyData;
  @override
  Future<void> saveOpening(Json data) async {
    openings.add(data);
    if (failure != null) throw StateError(failure!);
  }

  @override
  Future<Json> previewCSV(String contents) async {
    if (failure != null) throw StateError(failure!);
    return preview;
  }

  @override
  Future<Json> importCSV(Json data) async {
    imports.add(data);
    if (failure != null) throw StateError(failure!);
    return {'imported': (data['rows'] as List).length};
  }

  @override
  Future<void> undo(String id) async {
    undos.add(id);
    if (failure != null) throw StateError(failure!);
  }

  @override
  Future<String?> pick() async => contents;
  @override
  Future<void> requestReset(String email) async {
    requests++;
    if (pendingRecovery != null) await pendingRecovery!.future;
    if (failure != null) throw StateError(failure!);
  }

  @override
  Future<void> resetPassword(String token, String password) async {
    resets++;
    if (failure != null) throw StateError(failure!);
  }
}
