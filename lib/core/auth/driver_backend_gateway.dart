import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../security/security_diagnostics.dart';

const driverFunctionsRegion = 'us-central1';
const driverProfileApiBaseUrl = String.fromEnvironment(
  'TRUST_JUGGLER_API_BASE_URL',
);

typedef DriverCallableInvoker = Future<Map<String, dynamic>> Function(
  String name, [
  dynamic parameters,
]);

enum DriverBackendFailureKind {
  authentication,
  serviceUnavailable,
  profileMissing,
  permissionOrDeployment,
  unknown,
}

class DriverBackendException implements Exception {
  const DriverBackendException({
    required this.operation,
    required this.callableName,
    required this.correlationId,
    required this.code,
    required this.kind,
  });

  final String operation;
  final String callableName;
  final String correlationId;
  final String code;
  final DriverBackendFailureKind kind;
}

class DriverProfileSummary {
  const DriverProfileSummary({
    required this.accountStatus,
    required this.registrationStatus,
    required this.identityVerificationStatus,
    required this.deviceEnrollmentStatus,
    this.requiredDocumentsStatus = 'unknown',
    this.trainingStatus = 'unknown',
    this.riskStatus = 'ACTIVE',
    this.registrationStatusReason,
    this.identityVerificationStatusReason,
    this.requiredDocumentsStatusReason,
    this.trainingStatusReason,
  });

  final String accountStatus;
  final String registrationStatus;
  final String identityVerificationStatus;
  final String deviceEnrollmentStatus;
  final String requiredDocumentsStatus;
  final String trainingStatus;
  final String riskStatus;
  final String? registrationStatusReason;
  final String? identityVerificationStatusReason;
  final String? requiredDocumentsStatusReason;
  final String? trainingStatusReason;
}

/// Server-owned driver profile operations, injectable for widget tests.
abstract interface class DriverBackendGateway {
  Future<DriverProfileSummary> ensureAndGetProfile();
  Future<String> requestDeviceEnrollment(String platform);
}

abstract interface class DriverProfileStatusProvider {
  Future<DriverProfileSummary> getProfileStatus();
}

class FirebaseDriverBackendGateway implements DriverBackendGateway {
  FirebaseDriverBackendGateway(
    this.functions, {
    this.callableInvoker,
    this.profileStatusProvider,
  });

  final FirebaseFunctions? functions;
  final DriverCallableInvoker? callableInvoker;
  final DriverProfileStatusProvider? profileStatusProvider;

  @override
  Future<DriverProfileSummary> ensureAndGetProfile() async {
    // ensureDriverProfile returns {created: boolean}; don't request `void`.
    await _callMap('ensureDriverProfile');
    final response = await _callMap('getDriverProfile');
    final profileStatusProvider = this.profileStatusProvider;
    final profile = profileStatusProvider != null
        ? await profileStatusProvider.getProfileStatus()
        : DriverProfileSummary(
            accountStatus: response['accountStatus'] as String? ?? 'unknown',
            registrationStatus:
                response['registrationStatus'] as String? ?? 'unknown',
            identityVerificationStatus:
                response['identityVerificationStatus'] as String? ?? 'unknown',
            requiredDocumentsStatus:
                response['requiredDocumentsStatus'] as String? ?? 'unknown',
            trainingStatus: response['trainingStatus'] as String? ?? 'unknown',
            registrationStatusReason:
                response['registrationStatusReason'] as String?,
            identityVerificationStatusReason:
                response['identityVerificationStatusReason'] as String?,
            requiredDocumentsStatusReason:
                response['requiredDocumentsStatusReason'] as String?,
            trainingStatusReason: response['trainingStatusReason'] as String?,
            deviceEnrollmentStatus:
                response['deviceEnrollmentStatus'] as String? ?? 'unknown',
          );
    final risk = await _callMap('getRiskEventHistory');
    final riskStatus = risk['currentStatus'] as String? ?? 'UNKNOWN';
    return DriverProfileSummary(
      accountStatus: profile.accountStatus,
      registrationStatus: profile.registrationStatus,
      identityVerificationStatus: profile.identityVerificationStatus,
      deviceEnrollmentStatus: profile.deviceEnrollmentStatus,
      requiredDocumentsStatus: profile.requiredDocumentsStatus,
      trainingStatus: profile.trainingStatus,
      riskStatus: riskStatus,
      registrationStatusReason: profile.registrationStatusReason,
      identityVerificationStatusReason:
          profile.identityVerificationStatusReason,
      requiredDocumentsStatusReason: profile.requiredDocumentsStatusReason,
      trainingStatusReason: profile.trainingStatusReason,
    );
  }

  Future<Map<String, dynamic>> _callMap(String callableName) async {
    final correlationId = SecurityDiagnostics.newCorrelationId();
    try {
      return await _invokeMap(callableName);
    } on FirebaseFunctionsException catch (error) {
      SecurityDiagnostics.failure(
        operation: callableName,
        callableName: callableName,
        correlationId: correlationId,
        exceptionCode: error.code,
      );
      throw DriverBackendException(
        operation: callableName,
        callableName: callableName,
        correlationId: correlationId,
        code: error.code,
        kind: _failureKind(callableName, error.code),
      );
    } catch (_) {
      SecurityDiagnostics.failure(
        operation: callableName,
        callableName: callableName,
        correlationId: correlationId,
        exceptionCode: 'response-or-client-error',
      );
      throw DriverBackendException(
        operation: callableName,
        callableName: callableName,
        correlationId: correlationId,
        code: 'response-or-client-error',
        kind: DriverBackendFailureKind.unknown,
      );
    }
  }

  Future<Map<String, dynamic>> _invokeMap(
    String callableName, [
    dynamic parameters,
  ]) async {
    final invoke = callableInvoker;
    if (invoke != null) return invoke(callableName, parameters);
    final functionsInstance = functions;
    if (functionsInstance == null) {
      throw StateError('A FirebaseFunctions instance is required.');
    }
    final result = await functionsInstance
        .httpsCallable(callableName)
        .call<Map<String, dynamic>>(parameters);
    return result.data;
  }

  DriverBackendFailureKind _failureKind(String callableName, String code) {
    if (code == 'unauthenticated') {
      return DriverBackendFailureKind.authentication;
    }
    if (code == 'not-found' && callableName == 'getDriverProfile') {
      return DriverBackendFailureKind.profileMissing;
    }
    if (code == 'permission-denied' || code == 'not-found') {
      return DriverBackendFailureKind.permissionOrDeployment;
    }
    if (const {
      'unavailable',
      'deadline-exceeded',
      'internal',
      'resource-exhausted',
    }.contains(code)) {
      return DriverBackendFailureKind.serviceUnavailable;
    }
    return DriverBackendFailureKind.unknown;
  }

  @override
  Future<String> requestDeviceEnrollment(String platform) async {
    final callableName = 'requestDeviceEnrollment';
    final correlationId = SecurityDiagnostics.newCorrelationId();
    try {
      final response = await _invokeMap(callableName, {'platform': platform});
      return response['deviceEnrollmentId'] as String;
    } on FirebaseFunctionsException catch (error) {
      SecurityDiagnostics.failure(
        operation: callableName,
        callableName: callableName,
        correlationId: correlationId,
        exceptionCode: error.code,
      );
      throw DriverBackendException(
        operation: callableName,
        callableName: callableName,
        correlationId: correlationId,
        code: error.code,
        kind: _failureKind(callableName, error.code),
      );
    } catch (_) {
      SecurityDiagnostics.failure(
        operation: callableName,
        callableName: callableName,
        correlationId: correlationId,
        exceptionCode: 'response-or-client-error',
      );
      throw DriverBackendException(
        operation: callableName,
        callableName: callableName,
        correlationId: correlationId,
        code: 'response-or-client-error',
        kind: DriverBackendFailureKind.unknown,
      );
    }
  }
}

/// Reads the server-owned verification stages from the existing external API.
/// Missing API configuration leaves the extra eligibility statuses unknown.
class DriverProfileStatusApi implements DriverProfileStatusProvider {
  DriverProfileStatusApi({
    required String baseUrl,
    required this.auth,
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
  Future<DriverProfileSummary> getProfileStatus() async {
    final correlationId = SecurityDiagnostics.newCorrelationId();
    try {
      final profileUri = _profileUri();
      final token =
          await (tokenProvider?.call() ?? auth?.currentUser?.getIdToken());
      if (token == null || token.isEmpty) {
        throw DriverBackendException(
          operation: 'driverProfileStatus',
          callableName: 'GET /api/v1/driver/me',
          correlationId: correlationId,
          code: 'unauthenticated',
          kind: DriverBackendFailureKind.authentication,
        );
      }
      final response = await _client
          .get(
            profileUri,
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = _httpFailureCode(response.statusCode);
        SecurityDiagnostics.failure(
          operation: 'driverProfileStatus',
          callableName: 'GET /api/v1/driver/me',
          correlationId: correlationId,
          exceptionCode: code,
        );
        throw DriverBackendException(
          operation: 'driverProfileStatus',
          callableName: 'GET /api/v1/driver/me',
          correlationId: correlationId,
          code: code,
          kind: _httpFailureKind(response.statusCode),
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['driver'] is! Map<String, dynamic>) {
        throw const FormatException('Driver profile response is invalid.');
      }
      final profile = decoded['driver'] as Map<String, dynamic>;
      return DriverProfileSummary(
        accountStatus: profile['accountStatus'] as String? ?? 'unknown',
        registrationStatus:
            profile['registrationStatus'] as String? ?? 'unknown',
        identityVerificationStatus:
            profile['identityVerificationStatus'] as String? ?? 'unknown',
        requiredDocumentsStatus:
            profile['requiredDocumentsStatus'] as String? ?? 'unknown',
        trainingStatus: profile['trainingStatus'] as String? ?? 'unknown',
        deviceEnrollmentStatus:
            profile['deviceEnrollmentStatus'] as String? ?? 'unknown',
        registrationStatusReason:
            profile['registrationStatusReason'] as String?,
        identityVerificationStatusReason:
            profile['identityVerificationStatusReason'] as String?,
        requiredDocumentsStatusReason:
            profile['requiredDocumentsStatusReason'] as String?,
        trainingStatusReason: profile['trainingStatusReason'] as String?,
      );
    } on DriverBackendException {
      rethrow;
    } on TimeoutException {
      SecurityDiagnostics.failure(
        operation: 'driverProfileStatus',
        callableName: 'GET /api/v1/driver/me',
        correlationId: correlationId,
        exceptionCode: 'timeout',
      );
      throw DriverBackendException(
        operation: 'driverProfileStatus',
        callableName: 'GET /api/v1/driver/me',
        correlationId: correlationId,
        code: 'timeout',
        kind: DriverBackendFailureKind.serviceUnavailable,
      );
    } on http.ClientException {
      SecurityDiagnostics.failure(
        operation: 'driverProfileStatus',
        callableName: 'GET /api/v1/driver/me',
        correlationId: correlationId,
        exceptionCode: 'network-unavailable',
      );
      throw DriverBackendException(
        operation: 'driverProfileStatus',
        callableName: 'GET /api/v1/driver/me',
        correlationId: correlationId,
        code: 'network-unavailable',
        kind: DriverBackendFailureKind.serviceUnavailable,
      );
    } catch (_) {
      SecurityDiagnostics.failure(
        operation: 'driverProfileStatus',
        callableName: 'GET /api/v1/driver/me',
        correlationId: correlationId,
        exceptionCode: 'response-or-client-error',
      );
      throw DriverBackendException(
        operation: 'driverProfileStatus',
        callableName: 'GET /api/v1/driver/me',
        correlationId: correlationId,
        code: 'response-or-client-error',
        kind: DriverBackendFailureKind.unknown,
      );
    }
  }

  Uri _profileUri() {
    final baseUri = Uri.parse(_baseUrl);
    final isLoopback = const {
      'localhost',
      '127.0.0.1',
      '::1',
    }.contains(baseUri.host.toLowerCase());
    if (!baseUri.hasAuthority ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        (baseUri.scheme != 'https' &&
            !(baseUri.scheme == 'http' && isLoopback))) {
      throw const FormatException(
        'The driver API URL must use HTTPS (HTTP is allowed only for loopback development).',
      );
    }
    final normalizedBase = baseUri.replace(
      path: baseUri.path.endsWith('/') ? baseUri.path : '${baseUri.path}/',
    );
    return normalizedBase.resolve('api/v1/driver/me');
  }

  String _httpFailureCode(int statusCode) => switch (statusCode) {
    401 => 'unauthenticated',
    403 => 'permission-denied',
    404 => 'profile-missing',
    >= 500 => 'service-unavailable',
    _ => 'http-$statusCode',
  };

  DriverBackendFailureKind _httpFailureKind(int statusCode) =>
      switch (statusCode) {
        401 => DriverBackendFailureKind.authentication,
        403 => DriverBackendFailureKind.permissionOrDeployment,
        404 => DriverBackendFailureKind.profileMissing,
        >= 500 => DriverBackendFailureKind.serviceUnavailable,
        _ => DriverBackendFailureKind.unknown,
      };

  @visibleForTesting
  void close() => _client.close();
}
