import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../core/model/contracts.dart';

class FileExportDestination implements ExportDestination {
  @override
  Future<bool> save(String contents) async {
    final result = await FilePicker.saveFile(
      dialogTitle: 'Save your Pocketwise data',
      fileName: 'pocketwise-data.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: utf8.encode(contents),
    );
    // Web starts a browser download and returns null; it has no cancellation result.
    return kIsWeb || result != null;
  }
}
