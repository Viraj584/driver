import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/core/auth/account_access_gate.dart';
import 'package:rider_app/core/auth/auth_gateway.dart';
import 'package:rider_app/core/auth/driver_backend_gateway.dart';
import 'package:rider_app/core/security/secure_storage_service.dart';
import 'package:rider_app/core/security/session_manager.dart';
import 'package:rider_app/main.dart';

class _User implements User {
  @override
  String get uid => 'approved-driver';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements AuthGateway {
  _Auth([this.initialUser]);

  final changes = StreamController<User?>.broadcast();
  final User? initialUser;
  @override
  User? get currentUser => initialUser;
  @override
  Stream<User?> get userChanges => changes.stream;
  void signIn() => changes.add(_User());
  @override
  Future<void> sendPhoneCode(
    String phoneNumber,
    void Function(String) onCodeSent,
  ) async {}
  @override
  Future<void> verifyPhoneCode(String verificationId, String code) async {}
  @override
  Future<void> sendEmailLink(String email) async {}
  @override
  Future<void> finishEmailLink(String email, String link) async {}
  @override
  Future<void> signOut() async => changes.add(null);
}

class _Backend implements DriverBackendGateway {
  @override
  Future<DriverProfileSummary> ensureAndGetProfile() async =>
      const DriverProfileSummary(
        accountStatus: 'active',
        registrationStatus: 'approved',
        identityVerificationStatus: 'verified',
        deviceEnrollmentStatus: 'enrolled',
        requiredDocumentsStatus: 'verified',
        trainingStatus: 'complete',
      );
  @override
  Future<String> requestDeviceEnrollment(String platform) async => 'test-id';
}

class _Biometric implements BiometricGate {
  _Biometric(this.result);
  final bool result;
  @override
  Future<bool> canAuthenticate() async => true;
  @override
  Future<bool> authenticate() async => result;
}

class _Store implements SecureKeyValueStore {
  @override
  Future<String?> read({required String key}) async => null;
  @override
  Future<void> write({required String key, required String value}) async {}
  @override
  Future<void> delete({required String key}) async {}
}

Future<void> _pumpApprovedDriver(
  WidgetTester tester,
  bool biometricResult,
) async {
  final auth = _Auth();
  final session = SessionManager(
    biometric: _Biometric(biometricResult),
    secureStorage: SecureStorageService(store: _Store()),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: AccountAccessGate(
        firebaseConfigured: true,
        auth: auth,
        backend: _Backend(),
        child: RiderVerificationScreen(sessionManager: session),
      ),
    ),
  );
  expect(find.text('Biometric check'), findsNothing);
  auth.signIn();
  await tester.pumpAndSettle();
  expect(find.text('Biometric check'), findsOneWidget);
  expect(find.byKey(const Key('delivery-pool')), findsNothing);
  await tester.ensureVisible(find.text('Verify with biometrics'));
  await tester.tap(find.text('Verify with biometrics'));
  await tester.pumpAndSettle();
  if (biometricResult) {
    expect(session.isUnlocked, isTrue);
    expect(find.byKey(const Key('delivery-pool')), findsOneWidget);
  } else {
    expect(session.isUnlocked, isFalse);
    expect(find.byKey(const Key('delivery-pool')), findsNothing);
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await auth.changes.close();
  session.dispose();
}

void main() {
  testWidgets('approved backend profile still requires successful biometrics', (
    tester,
  ) async {
    await _pumpApprovedDriver(tester, true);
  });

  testWidgets('biometric cancellation keeps approved driver locked', (
    tester,
  ) async {
    await _pumpApprovedDriver(tester, false);
  });

  testWidgets('restored Firebase identity still starts behind biometric gate', (
    tester,
  ) async {
    final auth = _Auth(_User());
    final session = SessionManager(
      biometric: _Biometric(true),
      secureStorage: SecureStorageService(store: _Store()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          backend: _Backend(),
          child: RiderVerificationScreen(sessionManager: session),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Biometric check'), findsOneWidget);
    expect(session.state, SessionState.locked);
    expect(find.byKey(const Key('delivery-pool')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await auth.changes.close();
    session.dispose();
  });
}
