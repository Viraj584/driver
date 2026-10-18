import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/main.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rider_app/core/auth/auth_gateway.dart';
import 'package:rider_app/core/auth/driver_backend_gateway.dart';
import 'package:rider_app/core/security/secure_storage_service.dart';
import 'package:rider_app/core/security/session_manager.dart';

class FakeAuthenticator implements BiometricGate {
  bool available = true;
  Future<bool> Function()? onAuthenticate;
  int authenticateCalls = 0;

  @override
  Future<bool> canAuthenticate() async => available;

  @override
  Future<bool> authenticate() {
    authenticateCalls++;
    return onAuthenticate?.call() ?? Future.value(true);
  }
}

class MemoryStore implements SecureKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read({required String key}) async => values[key];
  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

class TestFirebaseUser implements User {
  @override
  String get uid => 'authenticated-driver-1234';
  @override
  String? get displayName => 'Verified Driver';
  @override
  String? get email => 'driver@example.test';
  @override
  String? get phoneNumber => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestAuthGateway implements AuthGateway, PasswordAuthGateway {
  final changes = StreamController<User?>.broadcast();
  User? activeUser;

  @override
  User? get currentUser => activeUser;
  @override
  Stream<User?> get userChanges => changes.stream;
  void authenticate() {
    activeUser = TestFirebaseUser();
    changes.add(activeUser);
  }

  @override
  Future<void> signInWithEmailPassword(String email, String password) async =>
      authenticate();
  @override
  Future<void> createEmailPasswordAccount(
    String email,
    String password,
  ) async => authenticate();
  @override
  Future<void> sendPhoneCode(
    String phoneNumber,
    void Function(String) onCodeSent,
  ) async => onCodeSent('verification-id');
  @override
  Future<void> verifyPhoneCode(String verificationId, String code) async =>
      authenticate();
  @override
  Future<void> sendEmailLink(String email) async {}
  @override
  Future<void> finishEmailLink(String email, String link) async =>
      authenticate();
  @override
  Future<void> signOut() async {
    activeUser = null;
    changes.add(null);
  }
}

class TestDriverBackend implements DriverBackendGateway {
  String riskStatus = 'ACTIVE';
  String registrationStatus = 'approved';
  @override
  Future<DriverProfileSummary> ensureAndGetProfile() async =>
      DriverProfileSummary(
        accountStatus: 'active',
        registrationStatus: registrationStatus,
        identityVerificationStatus: 'verified',
        requiredDocumentsStatus: 'verified',
        trainingStatus: 'complete',
        deviceEnrollmentStatus: 'enrolled',
        riskStatus: riskStatus,
      );
  @override
  Future<String> requestDeviceEnrollment(String platform) async =>
      'enrollment-id';
}

Future<void> showScreen(WidgetTester tester, FakeAuthenticator auth) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RiderVerificationScreen(
        authenticator: auth,
        secureStorage: SecureStorageService(store: MemoryStore()),
      ),
    ),
  );
}

Future<void> authenticate(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Verify with biometrics'));
  await tester.tap(find.text('Verify with biometrics'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('local demo login, navigation and logout stay outside Firebase', (
    tester,
  ) async {
    await tester.pumpWidget(
      TrustJugglerApp(
        demoMode: true,
        // DEMO_MODE must win even if Firebase is otherwise configured.
        firebaseConfigured: true,
        sessionManager: SessionManager(
          biometric: FakeAuthenticator(),
          secureStorage: SecureStorageService(store: MemoryStore()),
        ),
      ),
    );
    await tester.tap(find.text('ACCESS DRIVER PORTAL'));
    await tester.pumpAndSettle();
    expect(find.text('LOCAL DEMO — NOT SYNCED TO FIREBASE'), findsOneWidget);
    expect(find.text('virajb2005@gmail.com'), findsOneWidget);
    await tester.tap(find.text('Continue as demo driver'));
    await tester.pumpAndSettle();
    expect(find.text('Driver Delivery Pool'), findsOneWidget);
    expect(find.textContaining('9371736836'), findsNWidgets(2));
    expect(find.text('LOCAL DEMO — NOT SYNCED TO FIREBASE'), findsOneWidget);
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your workspace'), findsOneWidget);
    expect(find.text('Driver Delivery Pool'), findsNothing);
  });

  testWidgets('demo risk route runs locally without initializing Firebase', (
    tester,
  ) async {
    await tester.pumpWidget(
      TrustJugglerApp(demoMode: true, firebaseConfigured: true),
    );
    await tester.ensureVisible(find.text('Risk Engine').last);
    await tester.tap(find.text('Risk Engine').last);
    await tester.pumpAndSettle();
    expect(find.text('LOCAL DEMO — NOT SYNCED TO FIREBASE'), findsOneWidget);
    await tester.ensureVisible(find.text('Normal telemetry'));
    await tester.tap(find.text('Normal telemetry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Normal telemetry · score'), findsOneWidget);
    expect(find.textContaining('Firebase Functions setup'), findsNothing);
  });

  testWidgets(
    'successful Firebase login replaces login with delivery pool and Back avoids login',
    (tester) async {
      final auth = TestAuthGateway();
      await tester.pumpWidget(
        TrustJugglerApp(
          firebaseConfigured: true,
          authGateway: auth,
          driverBackend: TestDriverBackend(),
          sessionManager: SessionManager(
            biometric: FakeAuthenticator(),
            secureStorage: SecureStorageService(store: MemoryStore()),
          ),
        ),
      );
      await tester.tap(find.text('ACCESS DRIVER PORTAL'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use email and password'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Email address',
        ),
        'driver@example.test',
      );
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == 'Password',
        ),
        'valid-password',
      );
      await tester.ensureVisible(find.text('Log in with email'));
      await tester.tap(find.text('Log in with email'));
      await tester.pumpAndSettle();
      expect(find.text('Driver Delivery Pool'), findsOneWidget);
      expect(find.text('Verified Driver'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Choose your workspace'), findsOneWidget);
      expect(find.text('Welcome back, Driver'), findsNothing);
      await auth.changes.close();
    },
  );

  testWidgets(
    'restored Firebase session resolves profile before opening delivery pool',
    (tester) async {
      final auth = TestAuthGateway()..activeUser = TestFirebaseUser();
      await tester.pumpWidget(
        TrustJugglerApp(
          firebaseConfigured: true,
          authGateway: auth,
          driverBackend: TestDriverBackend(),
          sessionManager: SessionManager(
            biometric: FakeAuthenticator(),
            secureStorage: SecureStorageService(store: MemoryStore()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Driver Delivery Pool'), findsOneWidget);
      expect(find.text('Verified Driver'), findsOneWidget);
      await auth.changes.close();
    },
  );

  testWidgets('starts unauthenticated with protected content hidden', (
    tester,
  ) async {
    await showScreen(tester, FakeAuthenticator());
    expect(find.text('Biometric check'), findsOneWidget);
    expect(find.byKey(const Key('protected-session')), findsNothing);
    expect(find.byKey(const Key('delivery-pool')), findsNothing);
  });

  testWidgets('successful authentication grants access', (tester) async {
    await showScreen(tester, FakeAuthenticator());
    await authenticate(tester);
    expect(find.byKey(const Key('protected-session')), findsOneWidget);
    expect(find.byKey(const Key('delivery-pool')), findsOneWidget);
  });

  for (final outcome in <(String, Future<bool> Function())>[
    ('failure', () async => false),
    ('cancellation', () async => false),
    ('exception', () => Future<bool>.error(StateError('auth failed'))),
  ]) {
    testWidgets('${outcome.$1} does not grant access', (tester) async {
      final auth = FakeAuthenticator()..onAuthenticate = outcome.$2;
      await showScreen(tester, auth);
      await authenticate(tester);
      expect(find.byKey(const Key('protected-session')), findsNothing);
    });
  }

  testWidgets('logout revokes local access', (tester) async {
    await showScreen(tester, FakeAuthenticator());
    await authenticate(tester);
    await tester.ensureVisible(find.byKey(const Key('logout-button')));
    await tester.tap(find.byKey(const Key('logout-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('protected-session')), findsNothing);
    expect(
      find.text('Session locked. Verify your identity to continue.'),
      findsOneWidget,
    );
  });

  testWidgets('duplicate requests are ignored while authenticating', (
    tester,
  ) async {
    final completer = Completer<bool>();
    final auth = FakeAuthenticator()..onAuthenticate = () => completer.future;
    await showScreen(tester, auth);
    await tester.ensureVisible(find.text('Verify with biometrics'));
    await tester.tap(find.text('Verify with biometrics'));
    await tester.pump();
    expect(auth.authenticateCalls, 1);
    await tester.ensureVisible(find.text('Checking...'));
    await tester.tap(find.text('Checking...'));
    expect(auth.authenticateCalls, 1);
    completer.complete(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('protected-session')), findsOneWidget);
  });

  testWidgets('unavailable biometrics do not grant access', (tester) async {
    final auth = FakeAuthenticator()..available = false;
    await showScreen(tester, auth);
    await authenticate(tester);
    expect(find.byKey(const Key('protected-session')), findsNothing);
    expect(find.textContaining('Android Settings'), findsOneWidget);
    expect(auth.authenticateCalls, 0);
  });

  testWidgets('app background lifecycle locks the session', (tester) async {
    final manager = SessionManager(
      biometric: FakeAuthenticator(),
      secureStorage: SecureStorageService(store: MemoryStore()),
    );
    await tester.pumpWidget(
      MaterialApp(home: RiderVerificationScreen(sessionManager: manager)),
    );
    await manager.authenticate();
    await tester.pump();
    expect(manager.isUnlocked, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(manager.state, SessionState.locked);
    manager.dispose();
  });

  testWidgets('screen removes lifecycle observer when disposed', (
    tester,
  ) async {
    final manager = SessionManager(
      biometric: FakeAuthenticator(),
      secureStorage: SecureStorageService(store: MemoryStore()),
    );
    await tester.pumpWidget(
      MaterialApp(home: RiderVerificationScreen(sessionManager: manager)),
    );
    await manager.authenticate();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(manager.isUnlocked, isTrue);
    await manager.logout();
    manager.dispose();
  });
}
