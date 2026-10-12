import '../../../models/finance.dart';

abstract interface class RecordsRepository {
  Future<Json> balances(int page);
  Future<Json> history(int page);
  Future<void> saveOpening(Json data);
  Future<Json> previewCSV(String contents);
  Future<Json> importCSV(Json data);
  Future<void> undo(String id);
}

abstract interface class CSVSource {
  Future<String?> pick();
}
