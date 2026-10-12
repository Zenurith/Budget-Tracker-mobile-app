import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../models/finance.dart';
import '../services/api.dart';
import '../features/records/model/records_repository.dart';

class ApiRecordsRepository implements RecordsRepository {
  final Api api;
  ApiRecordsRepository(this.api);
  @override
  Future<Json> balances(int page) => api.request('GET', '/balances?page=$page');
  @override
  Future<Json> history(int page) =>
      api.request('GET', '/transaction-history?page=$page');
  @override
  Future<void> saveOpening(Json data) async {
    await api.request('PUT', '/balances/opening', body: data);
  }

  @override
  Future<Json> previewCSV(String contents) =>
      api.request('POST', '/imports/csv/preview', body: {'contents': contents});
  @override
  Future<Json> importCSV(Json data) =>
      api.request('POST', '/imports/csv/commit', body: data);
  @override
  Future<void> undo(String id) async {
    await api.request(
      'POST',
      '/transaction-history/${Uri.encodeComponent(id)}/undo',
    );
  }
}

class FileCSVSource implements CSVSource {
  @override
  Future<String?> pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (file == null) return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      if (bytes.length + chunk.length > 1000000) {
        throw const FormatException('Choose a CSV file no larger than 1 MB.');
      }
      bytes.add(chunk);
    }
    try {
      return utf8.decode(bytes.takeBytes());
    } on FormatException {
      throw const FormatException('Save the CSV using UTF-8 encoding.');
    }
  }
}
