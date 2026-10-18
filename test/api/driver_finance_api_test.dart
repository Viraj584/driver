import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rider_app/core/api/driver_finance_api.dart';

void main() {
  test('parses server balances and integer-paise payout values', () async {
    final api = DriverFinanceApi(
      baseUrl: 'https://api.example.test',
      tokenProvider: () async => 'firebase-id-token',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/earnings/summary');
        expect(request.headers['authorization'], 'Bearer firebase-id-token');
        return http.Response(
          jsonEncode({
            'availablePaise': 12345,
            'reservedPaise': 200,
            'processingPaise': 0,
            'paidPaise': 500,
            'failedPaise': 100,
            'releasedPaise': 100,
            'currency': 'INR',
          }),
          200,
        );
      }),
    );
    final result = await api.getSummary();
    expect(result.availablePaise, 12345);
    expect(result.paidPaise, 500);
    api.close();
  });

  test('malformed money values are rejected instead of rounded', () async {
    final api = DriverFinanceApi(
      baseUrl: 'https://api.example.test',
      tokenProvider: () async => 'token',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'availablePaise': 12.5,
            'reservedPaise': 0,
            'processingPaise': 0,
            'paidPaise': 0,
            'failedPaise': 0,
            'releasedPaise': 0,
          }),
          200,
        ),
      ),
    );
    await expectLater(api.getSummary(), throwsA(isA<DriverApiException>()));
    api.close();
  });

  test(
    'ambiguous payout timeout performs one POST and queries same key',
    () async {
      var postCount = 0;
      var statusCount = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          postCount++;
          expect(request.headers['idempotency-key'], 'stable-request-key-1234');
          expect(jsonDecode(request.body)['amountPaise'], 2300);
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return http.Response('{}', 202);
        }
        statusCount++;
        expect(
          request.url.path,
          '/api/v1/payout-requests/by-idempotency/stable-request-key-1234',
        );
        return http.Response(
          jsonEncode({
            'payout': {
              'id': 'request-1',
              'amountPaise': 2300,
              'status': 'awaiting_approval',
            },
          }),
          200,
        );
      });
      final api = DriverFinanceApi(
        baseUrl: 'https://api.example.test',
        tokenProvider: () async => 'token',
        client: client,
        timeout: const Duration(milliseconds: 5),
      );
      final payout = await api.requestPayout(
        amountPaise: 2300,
        payoutAccountId: 'primary',
        idempotencyKey: 'stable-request-key-1234',
      );
      expect(payout.id, 'request-1');
      expect(postCount, 1);
      expect(statusCount, 1);
      api.close();
    },
  );

  test(
    'unknown timeout result tells caller not to make another request',
    () async {
      var postCount = 0;
      final api = DriverFinanceApi(
        baseUrl: 'https://api.example.test',
        tokenProvider: () async => 'token',
        client: MockClient((request) async {
          if (request.method == 'POST') {
            postCount++;
            throw http.ClientException('connection interrupted');
          }
          return http.Response(
            jsonEncode({
              'error': {'code': 'not_found', 'message': 'Not found'},
            }),
            404,
          );
        }),
      );
      await expectLater(
        api.requestPayout(
          amountPaise: 2300,
          payoutAccountId: 'primary',
          idempotencyKey: 'stable-request-key-1234',
        ),
        throwsA(
          isA<DriverApiException>().having(
            (e) => e.code,
            'code',
            'payout_outcome_unknown',
          ),
        ),
      );
      expect(postCount, 1);
      api.close();
    },
  );

  test(
    'release builds reject HTTP endpoints and missing API URL fails safely',
    () async {
      final unconfigured = DriverFinanceApi(
        baseUrl: '',
        tokenProvider: () async => 'token',
      );
      await expectLater(
        unconfigured.getSummary(),
        throwsA(isA<DriverApiException>()),
      );
      unconfigured.close();
    },
  );
}
