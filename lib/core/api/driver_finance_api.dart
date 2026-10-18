import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const driverApiBaseUrl = String.fromEnvironment('TRUST_JUGGLER_API_BASE_URL');

class DriverApiException implements Exception {
  const DriverApiException(this.code, this.message, {this.statusCode});
  final String code;
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class DriverFinanceSummary {
  const DriverFinanceSummary({
    required this.availablePaise,
    required this.reservedPaise,
    required this.processingPaise,
    required this.paidPaise,
    required this.failedPaise,
    required this.releasedPaise,
  });

  final int availablePaise;
  final int reservedPaise;
  final int processingPaise;
  final int paidPaise;
  final int failedPaise;
  final int releasedPaise;

  factory DriverFinanceSummary.fromJson(Map<String, dynamic> json) =>
      DriverFinanceSummary(
        availablePaise: _requiredInt(json, 'availablePaise'),
        reservedPaise: _requiredInt(json, 'reservedPaise'),
        processingPaise: _requiredInt(json, 'processingPaise'),
        paidPaise: _requiredInt(json, 'paidPaise'),
        failedPaise: _requiredInt(json, 'failedPaise'),
        releasedPaise: _requiredInt(json, 'releasedPaise'),
      );
}

class DriverPayoutAccount {
  const DriverPayoutAccount({
    required this.id,
    required this.type,
    required this.maskedDestination,
    required this.status,
  });
  final String id;
  final String type;
  final String maskedDestination;
  final String status;

  factory DriverPayoutAccount.fromJson(Map<String, dynamic> json) =>
      DriverPayoutAccount(
        id: _requiredString(json, 'id'),
        type: _requiredString(json, 'accountType'),
        maskedDestination: _requiredString(json, 'maskedDestination'),
        status: _requiredString(json, 'status'),
      );
}

class DriverPayoutRecord {
  const DriverPayoutRecord({
    required this.id,
    required this.amountPaise,
    required this.status,
    this.utr,
  });
  final String id;
  final int amountPaise;
  final String status;
  final String? utr;

  factory DriverPayoutRecord.fromJson(Map<String, dynamic> json) =>
      DriverPayoutRecord(
        id: _requiredString(json, 'id'),
        amountPaise: _requiredInt(json, 'amountPaise'),
        status: _requiredString(json, 'status'),
        utr: json['utr'] is String ? json['utr'] as String : null,
      );
}

class DriverLedgerEntry {
  const DriverLedgerEntry({
    required this.id,
    required this.amountPaise,
    required this.type,
    required this.referenceId,
  });
  final String id;
  final int amountPaise;
  final String type;
  final String referenceId;

  factory DriverLedgerEntry.fromJson(Map<String, dynamic> json) =>
      DriverLedgerEntry(
        id: _requiredString(json, 'id'),
        amountPaise: _requiredInt(json, 'amountPaise'),
        type: _requiredString(json, 'type'),
        referenceId: _requiredString(json, 'referenceId'),
      );
}

class DriverFinancePage<T> {
  const DriverFinancePage({required this.items, required this.nextCursor});
  final List<T> items;
  final String? nextCursor;
}

abstract interface class DriverFinanceRepository {
  Future<DriverFinanceSummary> getSummary();
  Future<DriverFinancePage<DriverLedgerEntry>> getLedger({String? cursor});
  Future<List<DriverPayoutAccount>> getAccounts();
  Future<DriverPayoutAccount> setupAccount(Map<String, Object?> details);
  Future<DriverFinancePage<DriverPayoutRecord>> getPayouts({String? cursor});
  Future<DriverPayoutRecord> requestPayout({
    required int amountPaise,
    required String payoutAccountId,
    required String idempotencyKey,
  });
  Future<DriverPayoutRecord> getPayoutByIdempotency(String key);
}

class DriverFinanceApi implements DriverFinanceRepository {
  DriverFinanceApi({
    required String baseUrl,
    this.auth,
    http.Client? client,
    this.tokenProvider,
    this.timeout = const Duration(seconds: 12),
  }) : _baseUrl = baseUrl.trim(),
       _client = client ?? http.Client();

  final String _baseUrl;
  final FirebaseAuth? auth;
  final http.Client _client;
  final Future<String?> Function()? tokenProvider;
  final Duration timeout;

  @override
  Future<DriverFinanceSummary> getSummary() async =>
      DriverFinanceSummary.fromJson(await _getMap('/earnings/summary'));

  @override
  Future<DriverFinancePage<DriverLedgerEntry>> getLedger({
    String? cursor,
  }) async {
    final query = {'limit': '25'};
    if (cursor != null) {
      query['cursor'] = cursor;
    }
    final json = await _getMap('/earnings/ledger', query: query);
    return DriverFinancePage(
      items: _list(
        json,
        'items',
      ).map(DriverLedgerEntry.fromJson).toList(growable: false),
      nextCursor: json['nextCursor'] is String
          ? json['nextCursor'] as String
          : null,
    );
  }

  @override
  Future<List<DriverPayoutAccount>> getAccounts() async {
    final json = await _getMap('/payout-accounts');
    return _list(
      json,
      'items',
    ).map(DriverPayoutAccount.fromJson).toList(growable: false);
  }

  @override
  Future<DriverPayoutAccount> setupAccount(Map<String, Object?> details) async {
    final json = await _sendMap(
      'POST',
      '/payout-accounts/setup',
      body: details,
    );
    return DriverPayoutAccount.fromJson(_map(json['account']));
  }

  @override
  Future<DriverFinancePage<DriverPayoutRecord>> getPayouts({
    String? cursor,
  }) async {
    final query = {'limit': '25'};
    if (cursor != null) {
      query['cursor'] = cursor;
    }
    final json = await _getMap('/payout-requests', query: query);
    return DriverFinancePage(
      items: _list(
        json,
        'items',
      ).map(DriverPayoutRecord.fromJson).toList(growable: false),
      nextCursor: json['nextCursor'] is String
          ? json['nextCursor'] as String
          : null,
    );
  }

  /// A transport timeout is resolved by reading the same idempotency key.
  /// This method never retries the payout-creation POST.
  @override
  Future<DriverPayoutRecord> requestPayout({
    required int amountPaise,
    required String payoutAccountId,
    required String idempotencyKey,
  }) async {
    try {
      final json = await _sendMap(
        'POST',
        '/payout-requests',
        body: {'amountPaise': amountPaise, 'payoutAccountId': payoutAccountId},
        headers: {'Idempotency-Key': idempotencyKey},
      );
      return DriverPayoutRecord.fromJson(_map(json['payout']));
    } on _TransportFailure {
      try {
        return await getPayoutByIdempotency(idempotencyKey);
      } on DriverApiException catch (error) {
        if (error.statusCode == 404) {
          throw const DriverApiException(
            'payout_outcome_unknown',
            'We could not confirm the request yet. Check its status before creating another payout.',
          );
        }
        rethrow;
      }
    }
  }

  @override
  Future<DriverPayoutRecord> getPayoutByIdempotency(String key) async {
    final json = await _getMap(
      '/payout-requests/by-idempotency/${Uri.encodeComponent(key)}',
    );
    return DriverPayoutRecord.fromJson(_map(json['payout']));
  }

  Future<DriverPayoutRecord> getPayout(String id) async {
    final json = await _getMap('/payout-requests/${Uri.encodeComponent(id)}');
    return DriverPayoutRecord.fromJson(_map(json['payout']));
  }

  void close() => _client.close();

  static String newIdempotencyKey() {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(24, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  Future<Map<String, dynamic>> _getMap(
    String path, {
    Map<String, String>? query,
  }) => _sendMap('GET', path, query: query);

  Future<Map<String, dynamic>> _sendMap(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    Map<String, String> headers = const {},
  }) async {
    final base = Uri.tryParse(_baseUrl);
    if (base == null ||
        !base.hasAuthority ||
        !{'http', 'https'}.contains(base.scheme)) {
      throw const DriverApiException(
        'api_not_configured',
        'Earnings service is not configured. Contact support.',
      );
    }
    final localHttp =
        !kReleaseMode &&
        base.scheme == 'http' &&
        {'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host);
    if (base.scheme != 'https' && !localHttp) {
      throw const DriverApiException(
        'https_required',
        'The earnings service must use HTTPS.',
      );
    }
    final user = auth?.currentUser;
    final token = tokenProvider != null
        ? await tokenProvider!()
        : await user?.getIdToken();
    if (token == null || token.isEmpty) {
      throw const DriverApiException(
        'unauthenticated',
        'Sign in again to view driver earnings.',
      );
    }
    final uri = base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/$'), '')}/api/v1$path',
      queryParameters: query,
    );
    try {
      final request = http.Request(method, uri)
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          ...headers,
        })
        ..followRedirects = false;
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed)
          .timeout(timeout);
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const DriverApiException(
          'invalid_response',
          'Earnings service returned an invalid response.',
        );
      }
      if (response.statusCode >= 500) throw const _TransportFailure();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          throw DriverApiException(
            error['code'] is String
                ? error['code'] as String
                : 'request_failed',
            error['message'] is String
                ? error['message'] as String
                : 'Request failed.',
            statusCode: response.statusCode,
          );
        }
        throw DriverApiException(
          'request_failed',
          'Earnings request failed.',
          statusCode: response.statusCode,
        );
      }
      return decoded;
    } on TimeoutException {
      throw const _TransportFailure();
    } on http.ClientException {
      throw const _TransportFailure();
    } on FormatException {
      throw const DriverApiException(
        'invalid_response',
        'Earnings service returned an invalid response.',
      );
    }
  }
}

class _TransportFailure implements Exception {
  const _TransportFailure();
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  throw const DriverApiException(
    'invalid_response',
    'Earnings service returned an invalid response.',
  );
}

List<Map<String, dynamic>> _list(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) {
    throw const DriverApiException(
      'invalid_response',
      'Earnings service returned an invalid response.',
    );
  }
  return value.map(_map).toList(growable: false);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw const DriverApiException(
    'invalid_response',
    'Earnings service returned an invalid response.',
  );
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int && value >= 0) return value;
  throw const DriverApiException(
    'invalid_response',
    'Earnings service returned an invalid response.',
  );
}
