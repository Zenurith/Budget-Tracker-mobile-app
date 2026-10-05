import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/finance.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool network;
  ApiException(this.message, {this.statusCode, this.network = false});
  @override
  String toString() => message;
}

class Api {
  static String get defaultUrl =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:8000'
      : 'http://localhost:8000';
  final String baseUrl;
  final http.Client client;
  final FlutterSecureStorage storage;
  String? accessToken, refreshToken;
  Future<void>? _refreshing;
  int _session = 0;
  void Function(String path)? beforeRequest;
  Api({String? baseUrl, http.Client? client, FlutterSecureStorage? storage})
    : baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_URL',
            defaultValue: '',
          ).replaceAll(RegExp(r'/$'), ''),
      client = client ?? http.Client(),
      storage = storage ?? const FlutterSecureStorage();

  Future<void> restore() async {
    refreshToken = await storage.read(key: 'refresh_token');
    if (refreshToken != null) await _refresh();
  }

  Future<void> saveSession(Json session) async {
    accessToken = session['access_token'];
    refreshToken = session['refresh_token'];
    await storage.write(key: 'refresh_token', value: refreshToken);
  }

  Future<void> clear() async {
    _session++;
    accessToken = null;
    refreshToken = null;
    await storage.delete(key: 'refresh_token');
  }

  Future<void> _refresh() async {
    final session = _session;
    final result = await request(
      'POST',
      '/auth/refresh',
      body: {'refresh_token': refreshToken},
      retry: false,
    );
    if (session == _session) await saveSession(result);
  }

  Future<Json> request(
    String method,
    String path, {
    Json? body,
    bool retry = true,
  }) async {
    beforeRequest?.call(path);
    final session = _session;
    final uri = Uri.parse('${baseUrl.isEmpty ? defaultUrl : baseUrl}$path');
    final req = http.Request(method, uri)
      ..headers['Content-Type'] = 'application/json';
    if (accessToken != null) {
      req.headers['Authorization'] = 'Bearer $accessToken';
    }
    if (body != null) req.body = jsonEncode(body);
    http.Response response;
    try {
      response = await client
          .send(req)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ApiException(
        'The connection timed out. Please try again.',
        network: true,
      );
    } on http.ClientException {
      throw ApiException(
        'Cannot reach Pocketwise. Check your connection and that the API is running.',
        network: true,
      );
    }
    if (session != _session) {
      throw ApiException('The signed-in account changed.');
    }
    if (response.statusCode == 401 &&
        retry &&
        refreshToken != null &&
        (!path.startsWith('/auth/') ||
            path == '/auth/me' ||
            path == '/auth/me/export')) {
      _refreshing ??= _refresh();
      try {
        await _refreshing;
      } finally {
        _refreshing = null;
      }
      return request(method, path, body: body, retry: false);
    }
    Json decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Json;
    } on FormatException {
      throw ApiException(
        'The server returned an unreadable response. Please retry.',
        statusCode: response.statusCode,
        network: response.statusCode >= 200 && response.statusCode < 300,
      );
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        decoded['error']?['message'] ??
            'Something went wrong. Please try again.',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }
}
