import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:rider_app/core/network/api_client.dart';
import 'package:rider_app/core/network/api_config.dart';
import 'package:rider_app/core/auth/local_backend_auth_gateway.dart';
import 'package:rider_app/core/auth/local_backend_driver_gateway.dart';
import 'package:rider_app/core/deliveries/delivery_repository.dart';
import 'package:rider_app/core/risk/local_backend_risk_gateway.dart';
import 'package:rider_app/core/risk/risk_engine.dart';
import 'package:rider_app/features/driver/stitch_screens.dart';

void main() {
  group('ApiConfig & ApiClient', () {
    test('ApiConfig provides a valid baseUrl string', () {
      expect(ApiConfig.baseUrl, isNotEmpty);
      expect(ApiConfig.resolveBaseUrl(), equals(ApiConfig.baseUrl));
    });

    test('ApiClient decorates requests with Authorization Bearer header', () async {
      late http.Request capturedRequest;
      final mockHttp = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'status': 'OK'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:3000',
        httpClient: mockHttp,
      );
      client.setTokens(accessToken: 'sample-access-token');

      final res = await client.get('/api/test');
      expect(res['success'], isTrue);
      expect(capturedRequest.headers['authorization'], equals('Bearer sample-access-token'));
    });

    test('ApiClient parses structured error payloads into ApiException', () async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'VALIDATION_ERROR',
              'message': 'Invalid email format',
            },
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:3000',
        httpClient: mockHttp,
      );

      expect(
        () => client.post('/api/test'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'VALIDATION_ERROR')
              .having((e) => e.message, 'message', 'Invalid email format')
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });
  });

  group('LocalBackendAuthGateway', () {
    test('signInWithEmailPassword updates currentUser with claims', () async {
      final mockHttp = MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'token': 'jwt-access-123',
                'refreshToken': 'rt-456',
                'user': {
                  'id': 'usr-1',
                  'email': 'driver@test.com',
                  'role': 'driver',
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:3000',
        httpClient: mockHttp,
      );
      final auth = LocalBackendAuthGateway(apiClient: client);

      await auth.signInWithEmailPassword('driver@test.com', 'SecurePass123!');
      expect(auth.currentUser, isNotNull);
      expect(auth.currentUser!.uid, equals('usr-1'));
      expect(auth.currentUser!.email, equals('driver@test.com'));

      final tokenResult = await auth.currentUser!.getIdTokenResult();
      expect(tokenResult.claims?['admin'], isFalse);
    });

    test('admin user returns admin: true in IdTokenResult claims', () async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'token': 'jwt-admin-token',
              'user': {
                'id': 'admin-usr',
                'email': 'admin@trustjuggler.internal',
                'role': 'admin',
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:3000',
        httpClient: mockHttp,
      );
      final auth = LocalBackendAuthGateway(apiClient: client);

      await auth.signInWithEmailPassword('admin@trustjuggler.internal', 'AdminSecret123!');
      final tokenResult = await auth.currentUser!.getIdTokenResult();
      expect(tokenResult.claims?['admin'], isTrue);
    });

    test('signOut clears client tokens and resets currentUser to null', () async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'loggedOut': true},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:3000',
        httpClient: mockHttp,
      );
      client.setTokens(accessToken: 'token');
      final auth = LocalBackendAuthGateway(
        apiClient: client,
        initialUser: LocalBackendUser(uid: 'u-1', email: 'u@test.com'),
      );

      expect(auth.currentUser, isNotNull);
      await auth.signOut();
      expect(auth.currentUser, isNull);
      expect(client.accessToken, isNull);
    });
  });

  group('LocalBackendDriverGateway', () {
    test('ensureAndGetProfile parses DriverProfileSummary', () async {
      final mockHttp = MockClient((request) async {
        if (request.url.path == '/api/riders/ensure') {
          return http.Response(
            jsonEncode({'success': true, 'data': {'ensured': true}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/riders/me') {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'driver': {
                  'accountStatus': 'active',
                  'registrationStatus': 'approved',
                  'identityVerificationStatus': 'verified',
                  'deviceEnrollmentStatus': 'enrolled',
                  'riskStatus': 'ACTIVE',
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:3000',
        httpClient: mockHttp,
      );
      final gateway = LocalBackendDriverGateway(apiClient: client);

      final profile = await gateway.ensureAndGetProfile();
      expect(profile.accountStatus, equals('active'));
      expect(profile.registrationStatus, equals('approved'));
      expect(profile.riskStatus, equals('ACTIVE'));
    });
  });

  group('LocalBackendRiskGateway', () {
    test('submitEvent submits telemetry and returns RiskEventResult', () async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'requestId': 'req-999',
              'score': 15.0,
              'reasons': ['SPEED_ANOMALY'],
              'status': 'ACTIVE',
              'verificationRequired': false,
              'reviewRequired': false,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:3000',
        httpClient: mockHttp,
      );
      client.setTokens(accessToken: 'valid-token');
      final risk = LocalBackendRiskGateway(apiClient: client);

      final result = await risk.submitEvent(
        requestId: 'req-999',
        event: RiskEventType.unusualSpeed,
        poorLocationAccuracy: false,
      );

      expect(result.requestId, equals('req-999'));
      expect(result.score, equals(15.0));
      expect(result.status, equals(RiderRiskStatus.active));
      expect(result.reasons, contains('SPEED_ANOMALY'));
    });
  });

  group('LocalBackendDeliveryRepository', () {
    test('getDeliveries returns mapped list and acceptDelivery posts correctly', () async {
      String? acceptedId;
      final mockHttp = MockClient((request) async {
        if (request.url.path == '/api/deliveries' && request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'deliveries': [
                  {
                    'id': 'DEL-101',
                    'title': 'Server Delivery',
                    'pickup': 'Warehouse A',
                    'dropoff': 'Store B',
                    'amount': 450,
                    'distance': '5.0 km',
                    'eta': '20 min',
                    'serviceType': 'Express',
                    'recipientLabel': 'Alice',
                    'notes': 'Fragile',
                    'tags': 'High payout',
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/deliveries/DEL-101/accept') {
          acceptedId = 'DEL-101';
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'deliveryId': 'DEL-101', 'status': 'ACCEPTED'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:3000',
        httpClient: mockHttp,
      );
      final repo = LocalBackendDeliveryRepository(apiClient: client);

      final deliveries = await repo.getDeliveries();
      expect(deliveries.length, equals(1));
      expect(deliveries[0].id, equals('DEL-101'));
      expect(deliveries[0].title, equals('Server Delivery'));

      await repo.acceptDelivery('DEL-101');
      expect(acceptedId, equals('DEL-101'));
    });

    testWidgets('DriverDeliveryPoolScreen renders server accept button when deliveryRepository is present', (tester) async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'deliveries': [
                {
                  'id': 'DEL-LIVE-1',
                  'title': 'Live Order',
                  'pickup': 'Origin Hub',
                  'dropoff': 'Destination Site',
                  'amount': 300,
                  'distance': '2.5 km',
                  'eta': '10 min',
                  'serviceType': 'Standard',
                  'recipientLabel': 'Bob',
                  'notes': '',
                  'tags': 'Standard',
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:3000',
        httpClient: mockHttp,
      );
      final repo = LocalBackendDeliveryRepository(apiClient: client);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DriverDeliveryPoolScreen(
                driverIdentity: 'driver@test.com',
                deliveryRepository: repo,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('accept-delivery-button')), findsOneWidget);
      expect(find.text('ACCEPT DELIVERY (SERVER AUTHORIZED)'), findsOneWidget);
    });
  });
}
