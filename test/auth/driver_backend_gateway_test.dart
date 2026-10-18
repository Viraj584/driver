import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:rider_app/core/auth/driver_backend_gateway.dart';

void main() {
  test(
    'profile bootstrap consumes callable response maps with expected schema',
    () async {
      final calls = <String>[];
      final backend = FirebaseDriverBackendGateway(
        null,
        callableInvoker: (name, [parameters]) async {
          calls.add(name);
          if (name == 'ensureDriverProfile') return {'created': true};
          return {
            'role': 'driver',
            'accountStatus': 'active',
            'registrationStatus': 'approved',
            'identityVerificationStatus': 'verified',
            'requiredDocumentsStatus': 'verified',
            'trainingStatus': 'complete',
            'registrationStatusReason': null,
            'identityVerificationStatusReason': null,
            'requiredDocumentsStatusReason': null,
            'trainingStatusReason': null,
            'deviceEnrollmentStatus': 'enrolled',
          };
        },
      );

      final profile = await backend.ensureAndGetProfile();
      expect(calls, ['ensureDriverProfile', 'getDriverProfile']);
      expect(profile.accountStatus, 'active');
      expect(profile.registrationStatus, 'approved');
      expect(profile.identityVerificationStatus, 'verified');
      expect(profile.deviceEnrollmentStatus, 'enrolled');
      expect(profile.requiredDocumentsStatus, 'verified');
      expect(profile.trainingStatus, 'complete');
      expect(driverFunctionsRegion, 'us-central1');
    },
  );

  test(
    'external profile status API supplies document and training gates',
    () async {
      var sawAuthorization = false;
      final api = DriverProfileStatusApi(
        baseUrl: 'https://api.example.test',
        auth: null,
        tokenProvider: () async => 'test-token',
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/driver/me');
          sawAuthorization =
              request.headers['authorization'] == 'Bearer test-token';
          return http.Response(
            '{"driver":{"accountStatus":"active","registrationStatus":"approved","registrationStatusReason":null,"identityVerificationStatus":"verified","identityVerificationStatusReason":null,"requiredDocumentsStatus":"manual_review","requiredDocumentsStatusReason":"Review required","trainingStatus":"pending","trainingStatusReason":null,"deviceEnrollmentStatus":"enrolled"}}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final profile = await api.getProfileStatus();
      expect(sawAuthorization, isTrue);
      expect(profile.requiredDocumentsStatus, 'manual_review');
      expect(profile.requiredDocumentsStatusReason, 'Review required');
      expect(profile.trainingStatus, 'pending');
      api.close();
    },
  );

  test(
    'gateway bootstraps callable profile then uses expanded API status',
    () async {
      final calls = <String>[];
      final backend = FirebaseDriverBackendGateway(
        null,
        callableInvoker: (name, [parameters]) async {
          calls.add(name);
          return name == 'ensureDriverProfile'
              ? {'created': true}
              : {
                  'accountStatus': 'active',
                  'registrationStatus': 'registration_pending',
                  'identityVerificationStatus': 'identity_pending',
                  'deviceEnrollmentStatus': 'pending_review',
                };
        },
        profileStatusProvider: _FakeDriverProfileStatusProvider(
          const DriverProfileSummary(
            accountStatus: 'active',
            registrationStatus: 'approved',
            identityVerificationStatus: 'verified',
            requiredDocumentsStatus: 'verified',
            trainingStatus: 'complete',
            deviceEnrollmentStatus: 'enrolled',
          ),
        ),
      );

      final profile = await backend.ensureAndGetProfile();
      expect(calls, ['ensureDriverProfile', 'getDriverProfile']);
      expect(profile.registrationStatus, 'approved');
      expect(profile.requiredDocumentsStatus, 'verified');
      expect(profile.trainingStatus, 'complete');
    },
  );

  test('external profile status errors fail closed', () async {
    final api = DriverProfileStatusApi(
      baseUrl: 'https://api.example.test',
      auth: null,
      tokenProvider: () async => 'test-token',
      client: MockClient((_) async => http.Response('{}', 503)),
    );
    await expectLater(
      api.getProfileStatus(),
      throwsA(
        isA<DriverBackendException>().having(
          (error) => error.kind,
          'kind',
          DriverBackendFailureKind.serviceUnavailable,
        ),
      ),
    );
    api.close();
  });

  test(
    'profile API refuses cleartext remote URLs before reading auth token',
    () async {
      var tokenRead = false;
      var requestSent = false;
      final api = DriverProfileStatusApi(
        baseUrl: 'http://api.example.test',
        auth: null,
        tokenProvider: () async {
          tokenRead = true;
          return 'test-token';
        },
        client: MockClient((_) async {
          requestSent = true;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        api.getProfileStatus(),
        throwsA(
          isA<DriverBackendException>().having(
            (error) => error.kind,
            'kind',
            DriverBackendFailureKind.unknown,
          ),
        ),
      );
      expect(tokenRead, isFalse);
      expect(requestSent, isFalse);
      api.close();
    },
  );

  test('unexpected callable failures are sanitized and fail closed', () async {
    final backend = FirebaseDriverBackendGateway(
      null,
      callableInvoker: (name, [parameters]) async =>
          throw StateError('sensitive fixture'),
    );

    await expectLater(
      backend.ensureAndGetProfile(),
      throwsA(
        isA<DriverBackendException>()
            .having(
              (error) => error.kind,
              'kind',
              DriverBackendFailureKind.unknown,
            )
            .having((error) => error.code, 'code', 'response-or-client-error')
            .having(
              (error) => error.callableName,
              'callable',
              'ensureDriverProfile',
            ),
      ),
    );
  });
}

class _FakeDriverProfileStatusProvider implements DriverProfileStatusProvider {
  const _FakeDriverProfileStatusProvider(this.profile);

  final DriverProfileSummary profile;

  @override
  Future<DriverProfileSummary> getProfileStatus() async => profile;
}
