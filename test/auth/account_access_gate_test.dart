import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/core/auth/account_access_gate.dart';
import 'package:rider_app/core/auth/auth_gateway.dart';
import 'package:rider_app/core/auth/driver_backend_gateway.dart';

class StubUser implements User {
  @override
  String get uid => 'test-driver-uid';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthGateway
    implements AuthGateway, PasswordAuthGateway, GoogleAuthGateway {
  final changes = StreamController<User?>.broadcast();
  User? activeUser;
  Completer<void> sendCodeGate = Completer<void>()..complete();
  int sendCodeCalls = 0;
  int emailLinkCalls = 0;
  int signOutCalls = 0;
  String? verificationId;
  String? lastPhoneNumber;
  String? lastVerificationId;
  String? lastCode;
  Object? sendCodeError;
  Object? verifyCodeError;
  Object? passwordSignInError;
  Object? emailLinkError;
  Object? finishEmailLinkError;
  int passwordSignInCalls = 0;
  int passwordCreateCalls = 0;
  int googleSignInCalls = 0;
  bool googleCancelled = false;
  String? passwordEmail;
  String? passwordValue;

  @override
  User? get currentUser => activeUser;

  @override
  Stream<User?> get userChanges => changes.stream;

  void emitSignedIn() {
    activeUser = StubUser();
    changes.add(activeUser);
  }

  void emitSignedOut() {
    activeUser = null;
    changes.add(null);
  }

  @override
  Future<void> sendPhoneCode(
    String phoneNumber,
    void Function(String) onCodeSent,
  ) async {
    sendCodeCalls++;
    lastPhoneNumber = phoneNumber;
    final error = sendCodeError;
    if (error != null) throw error;
    if (!sendCodeGate.isCompleted) await sendCodeGate.future;
    verificationId ??= 'test-verification-id';
    onCodeSent(verificationId!);
  }

  @override
  Future<void> verifyPhoneCode(String verificationId, String code) async {
    lastVerificationId = verificationId;
    lastCode = code;
    final error = verifyCodeError;
    if (error != null) throw error;
    emitSignedIn();
  }

  @override
  Future<void> sendEmailLink(String email) async {
    emailLinkCalls++;
    final error = emailLinkError;
    if (error != null) throw error;
  }

  @override
  Future<void> finishEmailLink(String email, String link) async {
    final error = finishEmailLinkError;
    if (error != null) throw error;
  }

  @override
  Future<void> signInWithEmailPassword(String email, String password) async {
    passwordSignInCalls++;
    passwordEmail = email;
    passwordValue = password;
    if (passwordSignInError != null) throw passwordSignInError!;
    emitSignedIn();
  }

  @override
  Future<void> createEmailPasswordAccount(String email, String password) async {
    passwordCreateCalls++;
    passwordEmail = email;
    passwordValue = password;
    emitSignedIn();
  }

  @override
  Future<void> signInWithGoogle() async {
    googleSignInCalls++;
    if (googleCancelled) return;
    emitSignedIn();
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    emitSignedOut();
  }

  Future<void> close() => changes.close();
}

Finder textFieldWithLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> openEmailMethods(WidgetTester tester) async {
  final section = find.text('Use email and password');
  if (section.evaluate().isNotEmpty) {
    await tester.ensureVisible(section);
    await tester.tap(section);
    await tester.pumpAndSettle();
  }
}

class FakeDriverBackend implements DriverBackendGateway {
  int profileCalls = 0;
  String accountStatus = 'active';
  String registrationStatus = 'approved';
  String identityStatus = 'verified';
  String documentsStatus = 'verified';
  String trainingStatus = 'complete';
  String deviceStatus = 'enrolled';
  String riskStatus = 'ACTIVE';
  int failuresRemaining = 0;

  @override
  Future<DriverProfileSummary> ensureAndGetProfile() async {
    profileCalls++;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('private fixture detail');
    }
    return DriverProfileSummary(
      accountStatus: accountStatus,
      registrationStatus: registrationStatus,
      identityVerificationStatus: identityStatus,
      deviceEnrollmentStatus: deviceStatus,
      requiredDocumentsStatus: documentsStatus,
      trainingStatus: trainingStatus,
      riskStatus: riskStatus,
    );
  }

  @override
  Future<String> requestDeviceEnrollment(String platform) async =>
      'server-generated-id';
}

void main() {
  testWidgets('Firebase initialization failure does not enter local mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: false,
          initializationError: 'configuration-error',
          child: Text('protected app'),
        ),
      ),
    );
    expect(
      find.textContaining('Secure sign-in could not start'),
      findsOneWidget,
    );
    expect(
      find.text('DEVELOPMENT MODE • FIREBASE NOT CONFIGURED'),
      findsNothing,
    );
    expect(find.text('protected app'), findsNothing);
  });

  testWidgets('unconfigured app clearly labels local development mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: false,
          child: Text('local biometric screen'),
        ),
      ),
    );
    expect(
      find.text('DEVELOPMENT MODE • FIREBASE NOT CONFIGURED'),
      findsOneWidget,
    );
    expect(find.text('local biometric screen'), findsOneWidget);
    expect(find.text('FIREBASE ACCOUNT SIGN-IN'), findsNothing);
  });

  testWidgets('email password sign-in invokes Firebase gateway path', (
    tester,
  ) async {
    final auth = FakeAuthGateway();
    final backend = FakeDriverBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          backend: backend,
          child: const Text('protected app'),
        ),
      ),
    );
    await openEmailMethods(tester);
    await tester.enterText(
      textFieldWithLabel('Email address'),
      'rider@example.test',
    );
    await tester.enterText(
      textFieldWithLabel('Password'),
      'correct-horse-battery',
    );
    await tester.ensureVisible(find.text('Log in with email'));
    await tester.tap(find.text('Log in with email'));
    await tester.pumpAndSettle();
    expect(auth.passwordSignInCalls, 1);
    expect(auth.passwordEmail, 'rider@example.test');
    expect(auth.passwordValue, 'correct-horse-battery');
    expect(backend.profileCalls, 1);
    expect(find.text('protected app'), findsOneWidget);
    await auth.close();
  });

  testWidgets('email password account creation uses Firebase gateway path', (
    tester,
  ) async {
    final auth = FakeAuthGateway();
    final backend = FakeDriverBackend()
      ..registrationStatus = 'registration_pending';
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          startInSignUp: true,
          auth: auth,
          backend: backend,
          child: const Text('protected app'),
        ),
      ),
    );
    await openEmailMethods(tester);
    await tester.enterText(
      textFieldWithLabel('Email address'),
      'rider@example.test',
    );
    await tester.enterText(
      textFieldWithLabel('Password'),
      'correct-horse-battery',
    );
    await tester.ensureVisible(find.text('Create account with email'));
    await tester.tap(find.text('Create account with email'));
    await tester.pumpAndSettle();
    expect(auth.passwordCreateCalls, 1);
    expect(auth.passwordSignInCalls, 0);
    expect(find.text('Driver onboarding'), findsOneWidget);
    expect(find.text('protected app'), findsNothing);
    await auth.close();
  });

  testWidgets('account content waits for auth and server profile state', (
    tester,
  ) async {
    final auth = FakeAuthGateway();
    final backend = FakeDriverBackend();
    var cleanupCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          backend: backend,
          beforeSignOut: () async => cleanupCalled = true,
          child: const Text('protected app'),
        ),
      ),
    );
    expect(find.text('protected app'), findsNothing);
    auth.emitSignedIn();
    await tester.pumpAndSettle();
    expect(backend.profileCalls, 1);
    expect(find.text('protected app'), findsOneWidget);
    expect(find.textContaining('REGISTRATION: APPROVED'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(cleanupCalled, isTrue);
    expect(auth.signOutCalls, 1);
    expect(find.text('protected app'), findsNothing);
    await auth.close();
  });

  testWidgets(
    'eligible Firebase driver redirects once after trusted profile check',
    (tester) async {
      final auth = FakeAuthGateway();
      final backend = FakeDriverBackend();
      var redirects = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AccountAccessGate(
            firebaseConfigured: true,
            auth: auth,
            backend: backend,
            onDriverAccessGranted: (_) => redirects++,
            child: const Text('driver delivery pool'),
          ),
        ),
      );
      auth.emitSignedIn();
      await tester.pumpAndSettle();
      auth.changes.add(auth.activeUser);
      await tester.pumpAndSettle();
      expect(backend.profileCalls, 1);
      expect(redirects, 1);
      expect(find.text('driver delivery pool'), findsOneWidget);
      await auth.close();
    },
  );

  testWidgets('step-up risk status keeps otherwise approved driver locked', (
    tester,
  ) async {
    final auth = FakeAuthGateway();
    final backend = FakeDriverBackend()..riskStatus = 'LIVENESS_PENDING';
    var redirects = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          backend: backend,
          onDriverAccessGranted: (_) => redirects++,
          child: const Text('driver delivery pool'),
        ),
      ),
    );
    auth.emitSignedIn();
    await tester.pumpAndSettle();
    expect(redirects, 0);
    expect(find.text('driver delivery pool'), findsNothing);
    expect(find.textContaining('additional verification'), findsOneWidget);
    await auth.close();
  });

  testWidgets('Google cancellation stays on sign-in without a false success', (
    tester,
  ) async {
    final auth = FakeAuthGateway()..googleCancelled = true;
    var redirects = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          backend: FakeDriverBackend(),
          googleSignInAvailable: true,
          onDriverAccessGranted: (_) => redirects++,
          child: const Text('driver delivery pool'),
        ),
      ),
    );
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(auth.googleSignInCalls, 1);
    expect(redirects, 0);
    expect(find.text('driver delivery pool'), findsNothing);
    expect(find.textContaining('could not be completed'), findsNothing);
    await auth.close();
  });

  testWidgets('invalid email credentials stay on the login form', (
    tester,
  ) async {
    final auth = FakeAuthGateway()
      ..passwordSignInError = FirebaseAuthException(code: 'invalid-credential');
    var redirects = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          backend: FakeDriverBackend(),
          onDriverAccessGranted: (_) => redirects++,
          child: const Text('driver delivery pool'),
        ),
      ),
    );
    await openEmailMethods(tester);
    await tester.enterText(
      textFieldWithLabel('Email address'),
      'rider@example.test',
    );
    await tester.enterText(
      textFieldWithLabel('Password'),
      'incorrect-password',
    );
    await tester.ensureVisible(find.text('Log in with email'));
    await tester.tap(find.text('Log in with email'));
    await tester.pumpAndSettle();
    expect(redirects, 0);
    expect(
      find.text(
        'Email, password, phone code, or Google credential was not recognized.',
      ),
      findsOneWidget,
    );
    expect(find.text('driver delivery pool'), findsNothing);
    await auth.close();
  });

  testWidgets('admin route requires server authorization before access', (
    tester,
  ) async {
    final auth = FakeAuthGateway();
    var adminRedirects = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          adminAccess: true,
          auth: auth,
          verifyAdminAccess: (_) async {},
          onAdminAccessGranted: (_) => adminRedirects++,
          child: const Text('fleet audit dashboard'),
        ),
      ),
    );
    auth.emitSignedIn();
    await tester.pumpAndSettle();
    expect(adminRedirects, 1);
    expect(find.text('fleet audit dashboard'), findsOneWidget);
    await auth.close();
  });

  testWidgets('driver account cannot enter the admin route', (tester) async {
    final auth = FakeAuthGateway();
    var adminRedirects = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          adminAccess: true,
          auth: auth,
          verifyAdminAccess: (_) async => throw FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'admin required',
          ),
          onAdminAccessGranted: (_) => adminRedirects++,
          child: const Text('fleet audit dashboard'),
        ),
      ),
    );
    auth.emitSignedIn();
    await tester.pumpAndSettle();
    expect(adminRedirects, 0);
    expect(find.text('fleet audit dashboard'), findsNothing);
    expect(
      find.text('This account is not authorized for Fleet Command.'),
      findsOneWidget,
    );
    await auth.close();
  });

  testWidgets('stale sign-in event cannot override a later sign-out event', (
    tester,
  ) async {
    final auth = FakeAuthGateway();
    final backend = FakeDriverBackend();
    final lockGate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          backend: backend,
          beforeSignOut: () => lockGate.future,
          child: const Text('protected app'),
        ),
      ),
    );
    auth.emitSignedIn();
    await tester.pump();
    auth.emitSignedOut();
    await tester.pump();
    lockGate.complete();
    await tester.pumpAndSettle();
    expect(backend.profileCalls, 0);
    expect(find.text('Registered Mobile Number'), findsOneWidget);
    expect(find.text('protected app'), findsNothing);
    await auth.close();
  });

  testWidgets('pending registration cannot access protected driver content', (
    tester,
  ) async {
    final auth = FakeAuthGateway();
    final backend = FakeDriverBackend()
      ..registrationStatus = 'registration_pending';
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          backend: backend,
          child: const Text('protected app'),
        ),
      ),
    );
    auth.emitSignedIn();
    await tester.pumpAndSettle();
    expect(find.text('Driver onboarding'), findsOneWidget);
    expect(find.text('protected app'), findsNothing);
    await auth.close();
  });

  testWidgets(
    'missing document or training approval keeps protected content locked',
    (tester) async {
      final auth = FakeAuthGateway();
      final backend = FakeDriverBackend()..documentsStatus = 'not_started';
      await tester.pumpWidget(
        MaterialApp(
          home: AccountAccessGate(
            firebaseConfigured: true,
            auth: auth,
            backend: backend,
            child: const Text('protected app'),
          ),
        ),
      );
      auth.emitSignedIn();
      await tester.pumpAndSettle();
      expect(find.text('Required documents'), findsOneWidget);
      expect(find.text('protected app'), findsNothing);
      await auth.close();
    },
  );

  testWidgets('pending training keeps protected driver content locked', (
    tester,
  ) async {
    final auth = FakeAuthGateway();
    final backend = FakeDriverBackend()..trainingStatus = 'pending';
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          backend: backend,
          child: const Text('protected app'),
        ),
      ),
    );
    auth.emitSignedIn();
    await tester.pumpAndSettle();
    expect(find.text('Required training'), findsOneWidget);
    expect(find.text('protected app'), findsNothing);
    await auth.close();
  });

  testWidgets('profile bootstrap failure stays locked and can be retried', (
    tester,
  ) async {
    final auth = FakeAuthGateway();
    final backend = FakeDriverBackend()..failuresRemaining = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          backend: backend,
          child: const Text('protected app'),
        ),
      ),
    );
    auth.emitSignedIn();
    await tester.pumpAndSettle();
    expect(find.text('Driver account check failed'), findsOneWidget);
    expect(find.textContaining('private fixture detail'), findsNothing);
    expect(find.text('protected app'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(backend.profileCalls, 2);
    expect(find.text('protected app'), findsOneWidget);
    await auth.close();
  });

  testWidgets('profile bootstrap failure offers sign out', (tester) async {
    final auth = FakeAuthGateway();
    final backend = FakeDriverBackend()..failuresRemaining = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          backend: backend,
          child: const Text('protected app'),
        ),
      ),
    );
    auth.emitSignedIn();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 1);
    expect(find.text('protected app'), findsNothing);
    await auth.close();
  });

  testWidgets('phone flow displays verification input after code sent', (
    tester,
  ) async {
    final auth = FakeAuthGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          child: const Text('protected app'),
        ),
      ),
    );
    await tester.enterText(
      textFieldWithLabel('Registered Mobile Number'),
      '+15555550100',
    );
    await tester.ensureVisible(find.text('Get OTP'));
    await tester.tap(find.text('Get OTP'));
    await tester.pumpAndSettle();
    expect(auth.sendCodeCalls, 1);
    expect(auth.lastPhoneNumber, '+15555550100');
    expect(find.text('6-Digit Verification Code'), findsOneWidget);
    expect(
      find.text('SMS sent. Enter the code before it expires.'),
      findsOneWidget,
    );
    await auth.close();
  });

  testWidgets('successful phone OTP routes only after server profile is approved', (
    tester,
  ) async {
    final auth = FakeAuthGateway();
    var redirects = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          backend: FakeDriverBackend(),
          onDriverAccessGranted: (_) => redirects++,
          child: const Text('driver delivery pool'),
        ),
      ),
    );
    await tester.enterText(textFieldWithLabel('Registered Mobile Number'), '+15555550100');
    await tester.tap(find.text('Get OTP'));
    await tester.pumpAndSettle();
    await tester.enterText(textFieldWithLabel('6-Digit Verification Code'), '123456');
    await tester.tap(find.text('Verify & Access Shift'));
    await tester.pumpAndSettle();
    expect(redirects, 1);
    expect(find.text('driver delivery pool'), findsOneWidget);
    await auth.close();
  });

  testWidgets('mobile onboarding login remains responsive at 320 pixels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    final auth = FakeAuthGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          child: const SizedBox.shrink(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.enterText(textFieldWithLabel('Registered Mobile Number'), '+15555550100');
    await tester.ensureVisible(find.text('Get OTP'));
    expect(tester.takeException(), isNull);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await auth.close();
  });

  testWidgets('invalid phone input is rejected without making a request', (
    tester,
  ) async {
    final auth = FakeAuthGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          child: const Text('protected app'),
        ),
      ),
    );
    await tester.enterText(
      textFieldWithLabel('Registered Mobile Number'),
      '9876543210',
    );
    await tester.ensureVisible(find.text('Get OTP'));
    await tester.tap(find.text('Get OTP'));
    await tester.pumpAndSettle();
    expect(auth.sendCodeCalls, 0);
    expect(find.textContaining('international phone number'), findsOneWidget);
    expect(find.text('protected app'), findsNothing);
    await auth.close();
  });

  testWidgets('resend replaces the verification ID and preserves code digits', (
    tester,
  ) async {
    final auth = FakeAuthGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          child: const Text('protected app'),
        ),
      ),
    );
    await tester.enterText(
      textFieldWithLabel('Registered Mobile Number'),
      '+15555550100',
    );
    await tester.ensureVisible(find.text('Get OTP'));
    await tester.tap(find.text('Get OTP'));
    await tester.pumpAndSettle();
    expect(find.text('Resend 30'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    auth.verificationId = 'replacement-verification-id';
    await tester.ensureVisible(find.text('Resend'));
    await tester.tap(find.text('Resend'));
    await tester.pumpAndSettle();
    expect(auth.sendCodeCalls, 2);
    expect(find.text('Resend 30'), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == '6-Digit Verification Code',
      ),
      '001234',
    );
    await tester.ensureVisible(find.text('Verify & Access Shift'));
    await tester.tap(find.text('Verify & Access Shift'));
    await tester.pumpAndSettle();
    expect(auth.lastVerificationId, 'replacement-verification-id');
    expect(auth.lastCode, '001234');
    await auth.close();
  });

  testWidgets('duplicate authentication requests are ignored while pending', (
    tester,
  ) async {
    final auth = FakeAuthGateway()..sendCodeGate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          child: const Text('protected app'),
        ),
      ),
    );
    await tester.enterText(
      textFieldWithLabel('Registered Mobile Number'),
      '+15555550100',
    );
    await tester.ensureVisible(find.text('Get OTP'));
    await tester.tap(find.text('Get OTP'));
    await tester.pump();
    expect(find.text('Sending…'), findsOneWidget);
    await tester.tap(find.text('Sending…'), warnIfMissed: false);
    expect(auth.sendCodeCalls, 1);
    auth.sendCodeGate.complete();
    await tester.pumpAndSettle();
    expect(auth.sendCodeCalls, 1);
    expect(find.text('6-Digit Verification Code'), findsOneWidget);
    await auth.close();
  });

  testWidgets('invalid and expired phone codes remain signed out', (
    tester,
  ) async {
    final auth = FakeAuthGateway()
      ..verifyCodeError = FirebaseAuthException(
        code: 'invalid-verification-code',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          child: const Text('protected app'),
        ),
      ),
    );
    await tester.enterText(
      textFieldWithLabel('Registered Mobile Number'),
      '+15555550100',
    );
    await tester.ensureVisible(find.text('Get OTP'));
    await tester.tap(find.text('Get OTP'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == '6-Digit Verification Code',
      ),
      '123456',
    );
    await tester.ensureVisible(find.text('Verify & Access Shift'));
    await tester.tap(find.text('Verify & Access Shift'));
    await tester.pumpAndSettle();
    expect(find.text('That SMS code is invalid.'), findsOneWidget);
    expect(find.text('protected app'), findsNothing);
    await auth.close();
  });

  testWidgets('email link is requested using passwordless flow', (
    tester,
  ) async {
    final auth = FakeAuthGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          child: const Text('protected app'),
        ),
      ),
    );
    await openEmailMethods(tester);
    await tester.enterText(
      textFieldWithLabel('Email for sign-in link'),
      'driver@example.test',
    );
    await tester.ensureVisible(find.text('Send passwordless email link'));
    await tester.tap(find.text('Send passwordless email link'));
    await tester.pumpAndSettle();
    expect(auth.emailLinkCalls, 1);
    expect(find.text('Paste full sign-in link'), findsOneWidget);
    expect(find.textContaining('Sign-in link sent'), findsOneWidget);
    await auth.close();
  });

  testWidgets('expired email links fail without opening the app', (
    tester,
  ) async {
    final auth = FakeAuthGateway()
      ..finishEmailLinkError = FirebaseAuthException(
        code: 'expired-action-code',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          child: const Text('protected app'),
        ),
      ),
    );
    await openEmailMethods(tester);
    await tester.enterText(
      textFieldWithLabel('Email for sign-in link'),
      'driver@example.test',
    );
    await tester.ensureVisible(find.text('Send passwordless email link'));
    await tester.tap(find.text('Send passwordless email link'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'expired-link');
    await tester.ensureVisible(find.text('Complete email sign-in'));
    await tester.tap(find.text('Complete email sign-in'));
    await tester.pumpAndSettle();
    expect(
      find.text('That code or sign-in link expired. Request a new one.'),
      findsOneWidget,
    );
    expect(find.text('protected app'), findsNothing);
    await auth.close();
  });

  testWidgets('authentication exceptions show safe feedback without access', (
    tester,
  ) async {
    final auth = FakeAuthGateway()
      ..sendCodeError = FirebaseAuthException(code: 'too-many-requests');
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          firebaseConfigured: true,
          auth: auth,
          child: const Text('protected app'),
        ),
      ),
    );
    await tester.enterText(
      textFieldWithLabel('Registered Mobile Number'),
      '+15555550100',
    );
    await tester.ensureVisible(find.text('Get OTP'));
    await tester.tap(find.text('Get OTP'));
    await tester.pumpAndSettle();
    expect(
      find.text('Too many attempts. Wait before requesting another code.'),
      findsOneWidget,
    );
    expect(find.text('protected app'), findsNothing);
    await auth.close();
  });
}
