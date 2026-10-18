import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'api_config.dart';

class ApiException implements Exception {
  const ApiException({
    required this.message,
    required this.code,
    this.statusCode = 400,
    this.details,
  });

  final String message;
  final String code;
  final int statusCode;
  final dynamic details;

  @override
  String toString() => '$code ($statusCode): $message';
}

class ApiClient {
  ApiClient({
    String? baseUrl,
    http.Client? httpClient,
    this.onSessionExpired,
  }) : _baseUrl = baseUrl ?? ApiConfig.baseUrl,
       _httpClient = httpClient ?? http.Client();

  final String _baseUrl;
  final http.Client _httpClient;
  final void Function()? onSessionExpired;

  String? _accessToken;
  String? _refreshToken;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;

  void setTokens({String? accessToken, String? refreshToken}) {
    _accessToken = accessToken;
    if (refreshToken != null) {
      _refreshToken = refreshToken;
    }
  }

  void clearTokens() {
    _accessToken = null;
    _refreshToken = null;
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? queryParams,
  }) => _sendWithRetry('GET', path, queryParams: queryParams);

  Future<Map<String, dynamic>> post(
    String path, {
    dynamic body,
  }) => _sendWithRetry('POST', path, body: body);

  Future<Map<String, dynamic>> delete(
    String path, {
    dynamic body,
  }) => _sendWithRetry('DELETE', path, body: body);

  Future<Map<String, dynamic>> _sendWithRetry(
    String method,
    String path, {
    Map<String, String>? queryParams,
    dynamic body,
  }) async {
    try {
      return await _send(method, path, queryParams: queryParams, body: body);
    } on ApiException catch (e) {
      // If 401 and refresh token available, attempt refresh once
      if (e.statusCode == 401 && _refreshToken != null && path != '/api/auth/refresh' && path != '/api/auth/login') {
        final refreshed = await _tryRefreshToken();
        if (refreshed) {
          return await _send(method, path, queryParams: queryParams, body: body);
        } else {
          clearTokens();
          onSessionExpired?.call();
          rethrow;
        }
      }
      rethrow;
    }
  }

  Future<bool> _tryRefreshToken() async {
    final currentRefresh = _refreshToken;
    if (currentRefresh == null) return false;

    try {
      final uri = Uri.parse('$_baseUrl/api/auth/refresh');
      final res = await _httpClient.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': currentRefresh}),
      ).timeout(ApiConfig.timeout);

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final data = decoded['data'] as Map<String, dynamic>;
        _accessToken = data['token'] as String?;
        _refreshToken = data['refreshToken'] as String?;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? queryParams,
    dynamic body,
  }) async {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    var uri = Uri.parse('$_baseUrl$normalizedPath');
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams);
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (_accessToken != null && _accessToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }

    http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _httpClient.get(uri, headers: headers).timeout(ApiConfig.timeout);
          break;
        case 'POST':
          response = await _httpClient.post(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          ).timeout(ApiConfig.timeout);
          break;
        case 'DELETE':
          response = await _httpClient.delete(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          ).timeout(ApiConfig.timeout);
          break;
        default:
          throw ArgumentError('Unsupported HTTP method: $method');
      }
    } on TimeoutException {
      throw const ApiException(
        code: 'TIMEOUT',
        message: 'Request timed out. Check your backend server connection.',
        statusCode: 408,
      );
    } on SocketException catch (e) {
      throw ApiException(
        code: 'NETWORK_ERROR',
        message: 'Cannot reach backend at $_baseUrl. Ensure the local server is running. (${e.message})',
        statusCode: 503,
      );
    } on http.ClientException catch (e) {
      throw ApiException(
        code: 'CLIENT_ERROR',
        message: 'Network client error: ${e.message}',
        statusCode: 500,
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        code: 'UNKNOWN_ERROR',
        message: e.toString(),
        statusCode: 500,
      );
    }

    dynamic decodedBody;
    try {
      decodedBody = jsonDecode(response.body);
    } catch (_) {
      decodedBody = null;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decodedBody is Map<String, dynamic>) {
        return decodedBody;
      }
      return {'success': true, 'data': decodedBody};
    }

    // Error response
    String message = 'Server error (${response.statusCode})';
    String code = 'HTTP_${response.statusCode}';
    dynamic details;

    if (decodedBody is Map<String, dynamic> && decodedBody['error'] is Map) {
      final err = decodedBody['error'] as Map<String, dynamic>;
      message = err['message'] as String? ?? message;
      code = err['code'] as String? ?? code;
      details = err['details'];
    }

    throw ApiException(
      message: message,
      code: code,
      statusCode: response.statusCode,
      details: details,
    );
  }

  void close() {
    _httpClient.close();
  }
}
