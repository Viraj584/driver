import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'credential_policy.dart';
import '../security/security_diagnostics.dart';

/// Authentication actions needed by the account gate; replaceable in tests.
abstract interface class AuthGateway {
  Stream<User?> get userChanges;
  User? get currentUser;
  Future<void> sendPhoneCode(
    String phoneNumber,
    void Function(String) onCodeSent,
  );
  Future<void> verifyPhoneCode(String verificationId, String code);
  Future<void> sendEmailLink(String email);
  Future<void> finishEmailLink(String email, String link);
  Future<void> signOut();
}

abstract interface class PasswordAuthGateway {
  Future<void> signInWithEmailPassword(String email, String password);
  Future<void> createEmailPasswordAccount(String email, String password);
}

abstract interface class GoogleAuthGateway {
  Future<void> signInWithGoogle();
}

class FirebaseAuthGateway
    implements AuthGateway, PasswordAuthGateway, GoogleAuthGateway {
  FirebaseAuthGateway(this.auth);

  static Future<void>? _googleInitialization;

  final FirebaseAuth auth;
  int? _resendToken;
  final Map<String, String?> _phoneVerificationOwners = {};
  final CredentialOperationCoordinator _credentialCoordinator =
      CredentialOperationCoordinator();
  String? _emailLinkOwnerUid;
  bool _emailLinkPending = false;

  @override
  Future<void> signInWithEmailPassword(String email, String password) async {
    final normalizedEmail = email.trim();
    if (!normalizedEmail.contains('@') || password.isEmpty) {
      throw const FormatException('Enter a valid email and password.');
    }
    await auth.signInWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );
  }

  @override
  Future<void> createEmailPasswordAccount(String email, String password) async {
    final normalizedEmail = email.trim();
    if (!normalizedEmail.contains('@') || password.length < 8) {
      throw const FormatException(
        'Enter a valid email and a password with at least 8 characters.',
      );
    }
    await auth.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );
  }

  @override
  Future<void> signInWithGoogle() async {
    const serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
    if (serverClientId.isEmpty) {
      throw StateError(
        'Google sign-in needs GOOGLE_SERVER_CLIENT_ID and Firebase OAuth configuration.',
      );
    }
    _googleInitialization ??= GoogleSignIn.instance.initialize(
      serverClientId: serverClientId,
    );
    await _googleInitialization;
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError(
        'Google did not return an ID token. Check the OAuth client configuration.',
      );
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    await auth.signInWithCredential(credential);
  }

  @override
  User? get currentUser => auth.currentUser;

  @override
  Stream<User?> get userChanges => auth.userChanges();

  @override
  Future<void> sendPhoneCode(
    String phoneNumber,
    void Function(String) onCodeSent,
  ) async {
    final completed = Completer<void>();
    final initiatingUid = auth.currentUser?.uid;
    final normalizedNumber = normalizeE164PhoneNumber(phoneNumber);
    await auth.verifyPhoneNumber(
      phoneNumber: normalizedNumber,
      forceResendingToken: _resendToken,
      verificationCompleted: (credential) async {
        try {
          await _credentialCoordinator.run(() async {
            final user = auth.currentUser;
            final use = decideCredentialUse(
              initiatingUid: initiatingUid,
              currentUid: user?.uid,
            );
            if (use == CredentialUse.signIn) {
              await auth.signInWithCredential(credential);
            } else {
              await user!.linkWithCredential(credential);
            }
            _phoneVerificationOwners.removeWhere(
              (_, ownerUid) => ownerUid == initiatingUid,
            );
          });
          if (!completed.isCompleted) completed.complete();
        } catch (error, stackTrace) {
          SecurityDiagnostics.failure(
            operation: 'phoneAutomaticVerification',
            correlationId: SecurityDiagnostics.newCorrelationId(),
            exceptionCode: error is FirebaseAuthException
                ? error.code
                : 'automatic-verification-failed',
          );
          if (!completed.isCompleted) {
            completed.completeError(error, stackTrace);
          }
        }
      },
      verificationFailed: (error) {
        if (!completed.isCompleted) completed.completeError(error);
      },
      codeSent: (verificationId, resendToken) {
        _resendToken = resendToken;
        _phoneVerificationOwners[verificationId] = initiatingUid;
        onCodeSent(verificationId);
        if (!completed.isCompleted) completed.complete();
      },
      codeAutoRetrievalTimeout: (_) {
        if (!completed.isCompleted) {
          completed.completeError(
            FirebaseAuthException(
              code: 'session-expired',
              message: 'Phone verification timed out before a code was issued.',
            ),
          );
        }
      },
      timeout: const Duration(seconds: 60),
    );
    await completed.future;
  }

  @override
  Future<void> verifyPhoneCode(String verificationId, String code) async {
    final normalizedCode = normalizeSmsCode(code);
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: normalizedCode,
    );
    await _credentialCoordinator.run(() async {
      final user = auth.currentUser;
      final use = decideCredentialUse(
        initiatingUid: _phoneVerificationOwners[verificationId],
        currentUid: user?.uid,
      );
      if (use == CredentialUse.signIn) {
        await auth.signInWithCredential(credential);
      } else {
        await user!.linkWithCredential(credential);
      }
    });
    _phoneVerificationOwners.remove(verificationId);
  }

  @override
  Future<void> sendEmailLink(String email) async {
    const actionUrl = String.fromEnvironment('FIREBASE_EMAIL_ACTION_URL');
    const linkDomain = String.fromEnvironment('FIREBASE_LINK_DOMAIN');
    if (actionUrl.isEmpty) {
      throw StateError(
        'Configure FIREBASE_EMAIL_ACTION_URL for email sign-in.',
      );
    }
    _emailLinkOwnerUid = auth.currentUser?.uid;
    _emailLinkPending = true;
    await auth.sendSignInLinkToEmail(
      email: email,
      actionCodeSettings: ActionCodeSettings(
        url: actionUrl,
        handleCodeInApp: true,
        androidPackageName: 'com.trustjuggler.rider_app',
        androidInstallApp: true,
        androidMinimumVersion: '24',
        linkDomain: linkDomain.isEmpty ? null : linkDomain,
      ),
    );
  }

  @override
  Future<void> finishEmailLink(String email, String link) async {
    if (!auth.isSignInWithEmailLink(link)) {
      throw FirebaseAuthException(
        code: 'invalid-action-code',
        message: 'This is not a valid Trust Juggler sign-in link.',
      );
    }
    if (!_emailLinkPending) {
      throw StateError('Request a new email sign-in link from this app.');
    }
    final user = auth.currentUser;
    final use = decideCredentialUse(
      initiatingUid: _emailLinkOwnerUid,
      currentUid: user?.uid,
    );
    if (use == CredentialUse.signIn) {
      await auth.signInWithEmailLink(email: email, emailLink: link);
    } else {
      final credential = EmailAuthProvider.credentialWithLink(
        email: email,
        emailLink: link,
      );
      await user!.linkWithCredential(credential);
    }
    _emailLinkPending = false;
    _emailLinkOwnerUid = null;
  }

  @override
  Future<void> signOut() async {
    _phoneVerificationOwners.clear();
    _resendToken = null;
    _emailLinkPending = false;
    _emailLinkOwnerUid = null;
    await auth.signOut();
  }
}
