import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'auth_gateway.dart';
import 'credential_policy.dart';
import 'driver_backend_gateway.dart';
import '../security/security_diagnostics.dart';

/// Requires Firebase account sign-in and server profile bootstrap when Firebase
/// is configured. In local mode it labels the existing biometric demo clearly.
class AccountAccessGate extends StatefulWidget {
  const AccountAccessGate({
    required this.firebaseConfigured,
    required this.child,
    this.auth,
    this.backend,
    this.initializationError,
    this.beforeSignOut,
    this.startInSignUp = false,
    super.key,
  });

  final bool firebaseConfigured;
  final Widget child;
  final AuthGateway? auth;
  final DriverBackendGateway? backend;
  final String? initializationError;
  final Future<void> Function()? beforeSignOut;
  final bool startInSignUp;

  @override
  State<AccountAccessGate> createState() => _AccountAccessGateState();
}

class _AccountAccessGateState extends State<AccountAccessGate> {
  late final AuthGateway? _auth;
  late final DriverBackendGateway? _backend;
  StreamSubscription<User?>? _subscription;
  User? _user;
  String? _observedUserUid;
  String? _verificationId;
  String _message = '';
  bool _busy = false;
  bool _emailSent = false;
  bool _bootstrapped = false;
  bool _bootstrapInFlight = false;
  bool _profileBootstrapFailed = false;
  int _bootstrapOperation = 0;
  String? _profileBootstrapFailureMessage;
  String _registrationStatus = 'checking';
  String _accountStatus = 'unknown';
  String _identityStatus = 'unknown';
  String _documentsStatus = 'unknown';
  String _trainingStatus = 'unknown';
  String _deviceStatus = 'unknown';
  String _reviewReason = '';
  bool _isSignUp = false;
  final _phone = TextEditingController();
  final _smsCode = TextEditingController();
  final _email = TextEditingController();
  final _emailLink = TextEditingController();
  Timer? _smsTimeoutTimer;
  Timer? _resendCooldownTimer;
  int _resendCooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    _isSignUp = widget.startInSignUp;
    _auth =
        widget.auth ??
        (widget.firebaseConfigured
            ? FirebaseAuthGateway(FirebaseAuth.instance)
            : null);
    _backend = widget.backend;
    if (_auth != null) {
      _user = _auth.currentUser;
      _observedUserUid = _user?.uid;
      _subscription = _auth.userChanges.listen(_onUserChanged);
      if (_user != null) unawaited(_bootstrapProfile(_user!));
    }
  }

  Future<void> _onUserChanged(User? user) async {
    if (!mounted) return;
    if (_observedUserUid == user?.uid) return;
    _observedUserUid = user?.uid;
    final identityOperation = ++_bootstrapOperation;
    _bootstrapInFlight = false;
    try {
      // Invalidate any local gate whenever the Firebase identity changes.
      await widget.beforeSignOut?.call();
    } catch (_) {
      SecurityDiagnostics.failure(
        operation: 'lockSessionOnFirebaseIdentityChange',
        correlationId: SecurityDiagnostics.newCorrelationId(),
        exceptionCode: 'session-lock-failed',
      );
    }
    if (!mounted || identityOperation != _bootstrapOperation) return;
    setState(() {
      _user = user;
      _verificationId = null;
      _smsCode.clear();
      _smsTimeoutTimer?.cancel();
      _resendCooldownTimer?.cancel();
      _resendCooldownSeconds = 0;
      _bootstrapped = false;
      _profileBootstrapFailed = false;
      _profileBootstrapFailureMessage = null;
      _accountStatus = 'unknown';
      _registrationStatus = 'checking';
      _identityStatus = 'unknown';
      _documentsStatus = 'unknown';
      _trainingStatus = 'unknown';
      _deviceStatus = 'unknown';
      _reviewReason = '';
      _message = '';
    });
    if (user != null) await _bootstrapProfile(user);
  }

  Future<void> _bootstrapProfile(User user) async {
    if (_bootstrapped || _bootstrapInFlight || !widget.firebaseConfigured) {
      if (mounted && !widget.firebaseConfigured) {
        setState(() => _bootstrapped = true);
      }
      return;
    }
    _bootstrapInFlight = true;
    final operationId = ++_bootstrapOperation;
    if (mounted) {
      setState(() {
        _profileBootstrapFailed = false;
        _profileBootstrapFailureMessage = null;
      });
    }
    try {
      final backend =
          _backend ??
          FirebaseDriverBackendGateway(
            FirebaseFunctions.instanceFor(region: driverFunctionsRegion),
            profileStatusProvider: driverProfileApiBaseUrl.isEmpty
                ? null
                : DriverProfileStatusApi(
                    baseUrl: driverProfileApiBaseUrl,
                    auth: FirebaseAuth.instance,
                  ),
          );
      final profile = await backend.ensureAndGetProfile();
      if (mounted &&
          operationId == _bootstrapOperation &&
          _user?.uid == user.uid) {
        setState(() {
          _accountStatus = profile.accountStatus;
          _registrationStatus = profile.registrationStatus;
          _identityStatus = profile.identityVerificationStatus;
          _documentsStatus = profile.requiredDocumentsStatus;
          _trainingStatus = profile.trainingStatus;
          _deviceStatus = profile.deviceEnrollmentStatus;
          _reviewReason =
              profile.registrationStatusReason ??
              profile.identityVerificationStatusReason ??
              profile.requiredDocumentsStatusReason ??
              profile.trainingStatusReason ??
              '';
          _bootstrapped = true;
        });
      }
    } on DriverBackendException catch (error) {
      if (mounted && operationId == _bootstrapOperation) {
        setState(() {
          _profileBootstrapFailed = true;
          _profileBootstrapFailureMessage = _backendFailureMessage(error.kind);
        });
      }
    } on FirebaseFunctionsException catch (error) {
      final correlationId = SecurityDiagnostics.newCorrelationId();
      SecurityDiagnostics.failure(
        operation: 'driverProfileBootstrap',
        callableName: 'unknownCallable',
        correlationId: correlationId,
        exceptionCode: error.code,
      );
      if (mounted && operationId == _bootstrapOperation) {
        setState(() {
          _profileBootstrapFailed = true;
          _profileBootstrapFailureMessage = _backendFailureMessage(
            _classifyFunctionError(error.code),
          );
        });
      }
    } catch (_) {
      SecurityDiagnostics.failure(
        operation: 'driverProfileBootstrap',
        callableName: 'unknownCallable',
        correlationId: SecurityDiagnostics.newCorrelationId(),
        exceptionCode: 'unexpected-client-error',
      );
      if (mounted && operationId == _bootstrapOperation) {
        setState(() {
          _profileBootstrapFailed = true;
          _profileBootstrapFailureMessage = 'We could not confirm your driver account. Your session remains locked. Retry or sign out.';
        });
      }
    } finally {
      if (operationId == _bootstrapOperation) _bootstrapInFlight = false;
    }
  }

  String _backendFailureMessage(DriverBackendFailureKind kind) =>
      switch (kind) {
        DriverBackendFailureKind.authentication =>
          'Your sign-in could not be confirmed. Sign out and sign in again.',
        DriverBackendFailureKind.serviceUnavailable => 'The driver service is temporarily unavailable. Check your connection and retry.',
        DriverBackendFailureKind.profileMissing => 'The server could not find your driver profile. Retry, or sign out and contact support if this continues.',
        DriverBackendFailureKind.permissionOrDeployment => 'The driver service is not available for this account. Retry later or contact support.',
        DriverBackendFailureKind.unknown => 'We could not confirm your driver account. Your session remains locked. Retry or sign out.',
      };

  DriverBackendFailureKind _classifyFunctionError(String code) =>
      switch (code) {
        'unauthenticated' => DriverBackendFailureKind.authentication,
        'unavailable' ||
        'deadline-exceeded' ||
        'internal' ||
        'resource-exhausted' => DriverBackendFailureKind.serviceUnavailable,
        'permission-denied' ||
        'not-found' => DriverBackendFailureKind.permissionOrDeployment,
        _ => DriverBackendFailureKind.unknown,
      };

  Future<void> _perform(
    Future<void> Function() action, {
    required String operation,
    String? callableName,
  }) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _message = '';
    });
    final correlationId = SecurityDiagnostics.newCorrelationId();
    try {
      await action();
    } on FirebaseAuthException catch (error) {
      SecurityDiagnostics.failure(
        operation: operation,
        correlationId: correlationId,
        exceptionCode: error.code,
      );
      if (mounted) setState(() => _message = _authMessage(error.code));
    } on FormatException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on FirebaseFunctionsException catch (error) {
      SecurityDiagnostics.failure(
        operation: operation,
        callableName: callableName,
        correlationId: correlationId,
        exceptionCode: error.code,
      );
      if (mounted) {
        setState(
          () => _message = _backendFailureMessage(
            _classifyFunctionError(error.code),
          ),
        );
      }
    } on DriverBackendException catch (error) {
      if (mounted) {
        setState(() => _message = _backendFailureMessage(error.kind));
      }
    } on StateError catch (error) {
      if (mounted) {
        setState(() => _message = error.message);
      }
    } catch (_) {
      SecurityDiagnostics.failure(
        operation: operation,
        callableName: callableName,
        correlationId: correlationId,
        exceptionCode: 'unexpected-operation-error',
      );
      if (mounted) {
        setState(
          () => _message = 'Request could not be completed. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authMessage(String code) => switch (code) {
    'invalid-verification-code' => 'That SMS code is invalid.',
    'session-expired' || 'expired-action-code' =>
      'That code or sign-in link expired. Request a new one.',
    'invalid-action-code' ||
    'invalid-credential' => 'That code or sign-in link is invalid or expired.',
    'too-many-requests' =>
      'Too many attempts. Wait before requesting another code.',
    'invalid-phone-number' ||
    'invalid-email' => 'Check the phone number or email address.',
    'network-request-failed' =>
      'Network error. Check your connection and retry.',
    'captcha-check-failed' ||
    'missing-client-identifier' ||
    'invalid-app-credential' => 'App verification could not be completed. Check Google Play services and retry; if it continues, contact support.',
    'app-not-authorized' || 'operation-not-allowed' => 'Phone sign-in is not enabled for this app configuration. Contact support.',
    'quota-exceeded' => 'SMS quota has been reached. Wait and retry later, or use a configured test number.',
    'account-exists-with-different-credential' ||
    'credential-already-in-use' ||
    'user-mismatch' => 'This sign-in method belongs to another account. Sign into that account first; accounts are not merged automatically.',
    _ => 'Sign-in could not be completed. Check your details and retry.',
  };

  Future<void> _requestPhoneCode({required String operation}) async {
    await _perform(
      () => _auth!.sendPhoneCode(
        normalizeE164PhoneNumber(_phone.text),
        _onCodeSent,
      ),
      operation: operation,
    );
  }

  void _onCodeSent(String verificationId) {
    if (!mounted) return;
    setState(() {
      _verificationId = verificationId;
      _smsCode.clear();
      _message = 'SMS sent. Enter the code before it expires.';
      _resendCooldownSeconds = 30;
    });
    _smsTimeoutTimer?.cancel();
    _smsTimeoutTimer = Timer(const Duration(seconds: 60), () {
      if (mounted && _verificationId != null) {
        setState(
          () => _message = 'SMS auto-retrieval timed out. Enter the code if received, or request a new one.',
        );
      }
    });
    _resendCooldownTimer?.cancel();
    _resendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCooldownSeconds = (_resendCooldownSeconds - 1).clamp(0, 30);
        if (_resendCooldownSeconds == 0) timer.cancel();
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _smsTimeoutTimer?.cancel();
    _resendCooldownTimer?.cancel();
    _phone.dispose();
    _smsCode.dispose();
    _email.dispose();
    _emailLink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.initializationError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Secure sign-in could not start. Access is unavailable. Restart the app or contact support.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (!widget.firebaseConfigured) {
      return Column(
        children: [
          const _ModeBanner(text: 'DEVELOPMENT MODE • FIREBASE NOT CONFIGURED'),
          Expanded(child: widget.child),
        ],
      );
    }
    if (_user != null) {
      if (_profileBootstrapFailed) {
        return _ProfileBootstrapFailureScreen(
          message: _profileBootstrapFailureMessage ?? 'We could not confirm your driver account. Your session remains locked.',
          onRetry: _bootstrapInFlight ? null : () => _bootstrapProfile(_user!),
          onSignOut: _busy
              ? null
              : () => _perform(() async {
                  await widget.beforeSignOut?.call();
                  await _auth!.signOut();
                }, operation: 'firebaseSignOut'),
        );
      }
      if (!_bootstrapped) {
        return Scaffold(
          backgroundColor: const Color(0xFF0B1020),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Checking your driver account…'),
              ],
            ),
          ),
        );
      }
      return Column(
        children: [
          Material(
            color: const Color(0xFF141C30),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: _ModeBanner(
                      text:
                          'SIGNED IN • REGISTRATION: ${_registrationStatus.toUpperCase()}',
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _perform(() async {
                            await widget.beforeSignOut?.call();
                            await _auth!.signOut();
                          }, operation: 'firebaseSignOut'),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
          Material(
            color: const Color(0xFF141C30),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'DEVICE ENROLLMENT: ${_deviceStatus.toUpperCase()} · Approval is server controlled.',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _perform(
                            () async {
                              final platform = switch (defaultTargetPlatform) {
                                TargetPlatform.android => 'android',
                                TargetPlatform.iOS => 'ios',
                                _ => throw UnsupportedError(
                                  'Device enrollment is available only for Android or iOS.',
                                ),
                              };
                              final backend =
                                  _backend ??
                                  FirebaseDriverBackendGateway(
                                    FirebaseFunctions.instanceFor(
                                      region: driverFunctionsRegion,
                                    ),
                                  );
                              final enrollmentId = await backend
                                  .requestDeviceEnrollment(platform);
                              if (mounted) {
                                setState(() {
                                  _deviceStatus = 'pending_review';
                                  _message =
                                      'Device request submitted for review ($enrollmentId). This does not prove device integrity.';
                                });
                              }
                            },
                            operation: 'requestDeviceEnrollment',
                            callableName: 'requestDeviceEnrollment',
                          ),
                    child: const Text('Request device review'),
                  ),
                ],
              ),
            ),
          ),
          Material(
            color: const Color(0xFF0B1020),
            child: ExpansionTile(
              title: const Text('Link another sign-in method'),
              subtitle: const Text(
                'Verified credentials stay on this Firebase account.',
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email to link',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _perform(() async {
                                await _auth!.sendEmailLink(_email.text.trim());
                                if (mounted) {
                                  setState(() {
                                    _emailSent = true;
                                    _message = 'Email link sent. Paste the link below to attach this verified email to your account.';
                                  });
                                }
                              }, operation: 'linkEmailSend'),
                        child: const Text('Send email link'),
                      ),
                      if (_emailSent) ...[
                        TextField(
                          controller: _emailLink,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'Paste full email link',
                          ),
                        ),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _perform(
                                  () => _auth!.finishEmailLink(
                                    _email.text.trim(),
                                    _emailLink.text.trim(),
                                  ),
                                  operation: 'linkEmailComplete',
                                ),
                          child: const Text('Verify and link email'),
                        ),
                      ],
                      TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone number to link (+country code)',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _busy || _resendCooldownSeconds > 0
                            ? null
                            : () => _requestPhoneCode(
                                operation: 'linkPhoneCodeRequest',
                              ),
                        child: Text(
                          _resendCooldownSeconds > 0
                              ? 'Resend in ${_resendCooldownSeconds}s'
                              : 'Send phone verification code',
                        ),
                      ),
                      if (_verificationId != null) ...[
                        TextField(
                          controller: _smsCode,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'SMS code to link',
                          ),
                        ),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _perform(
                                  () => _auth!.verifyPhoneCode(
                                    _verificationId!,
                                    normalizeSmsCode(_smsCode.text),
                                  ),
                                  operation: 'linkPhoneCodeVerify',
                                ),
                          child: const Text('Verify and link phone'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _driverEligible
                ? widget.child
                : _OnboardingStatus(
                    accountStatus: _accountStatus,
                    registrationStatus: _registrationStatus,
                    identityStatus: _identityStatus,
                    documentsStatus: _documentsStatus,
                    trainingStatus: _trainingStatus,
                    deviceStatus: _deviceStatus,
                    reviewReason: _reviewReason,
                  ),
          ),
        ],
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _ModeBanner(text: 'FIREBASE ACCOUNT SIGN-IN'),
                const SizedBox(height: 24),
                Text(
                  _isSignUp ? 'Driver onboarding' : 'Driver account',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Sign Up')),
                    ButtonSegment(value: false, label: Text('Log In')),
                  ],
                  selected: {_isSignUp},
                  onSelectionChanged: _busy
                      ? null
                      : (selection) =>
                            setState(() => _isSignUp = selection.first),
                ),
                const SizedBox(height: 10),
                Text(
                  _isSignUp
                      ? 'Create an account with a verified phone or passwordless email link. Firebase handles account creation. This does not approve driver registration or device trust.'
                      : 'Continue with a verified phone or passwordless email link. Firebase handles account sign-in. This does not approve driver registration or device trust.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone number (+country code)',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed:
                      _busy ||
                          (_verificationId != null &&
                              _resendCooldownSeconds > 0)
                      ? null
                      : () => _requestPhoneCode(operation: 'phoneCodeRequest'),
                  child: Text(
                    _busy
                        ? 'Please wait…'
                        : _verificationId == null
                        ? 'Send SMS code'
                        : _resendCooldownSeconds > 0
                        ? 'Resend in ${_resendCooldownSeconds}s'
                        : 'Resend SMS code',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.g_mobiledata),
                  label: const Text('Google sign-in is not configured'),
                ),
                if (_verificationId != null) ...[
                  TextField(
                    controller: _smsCode,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'SMS verification code',
                    ),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _perform(
                            () => _auth!.verifyPhoneCode(
                              _verificationId!,
                              normalizeSmsCode(_smsCode.text),
                            ),
                            operation: 'phoneCodeVerify',
                          ),
                    child: const Text('Verify SMS code'),
                  ),
                ],
                const Divider(height: 32, color: Colors.white24),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email address'),
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _perform(() async {
                          await _auth!.sendEmailLink(_email.text.trim());
                          if (mounted) {
                            setState(() {
                              _emailSent = true;
                              _message = 'Sign-in link sent. Copy its full URL into the field below if this app did not open automatically.';
                            });
                          }
                        }, operation: 'emailLinkRequest'),
                  child: const Text('Send passwordless email link'),
                ),
                if (_emailSent) ...[
                  TextField(
                    controller: _emailLink,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Paste full sign-in link',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _perform(
                            () => _auth!.finishEmailLink(
                              _email.text.trim(),
                              _emailLink.text.trim(),
                            ),
                            operation: 'emailLinkComplete',
                          ),
                    child: const Text('Complete email sign-in'),
                  ),
                ],
                if (_message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _message,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _driverEligible =>
      _accountStatus == 'active' &&
      _registrationStatus == 'approved' &&
      _identityStatus == 'verified' &&
      _documentsStatus == 'verified' &&
      _trainingStatus == 'complete' &&
      _deviceStatus == 'enrolled';
}

class _ProfileBootstrapFailureScreen extends StatelessWidget {
  const _ProfileBootstrapFailureScreen({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0B1020),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 44,
                  color: Color(0xFF42D6B5),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Driver account check failed',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, height: 1.5),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                OutlinedButton.icon(
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _OnboardingStatus extends StatelessWidget {
  const _OnboardingStatus({
    required this.accountStatus,
    required this.registrationStatus,
    required this.identityStatus,
    required this.documentsStatus,
    required this.trainingStatus,
    required this.deviceStatus,
    required this.reviewReason,
  });

  final String accountStatus;
  final String registrationStatus;
  final String identityStatus;
  final String documentsStatus;
  final String trainingStatus;
  final String deviceStatus;
  final String reviewReason;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Card(
          color: const Color(0xFF141C30),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.assignment_outlined,
                  color: Color(0xFF42D6B5),
                  size: 38,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Driver onboarding',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Protected driver features remain locked until the backend confirms all required approvals.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, height: 1.45),
                ),
                const SizedBox(height: 16),
                _statusLine('Account', accountStatus),
                _statusLine('Registration', registrationStatus),
                _statusLine('Identity verification', identityStatus),
                _statusLine('Required documents', documentsStatus),
                _statusLine('Required training', trainingStatus),
                _statusLine('Device enrollment', deviceStatus),
                const SizedBox(height: 12),
                Text(
                  _nextStep,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, height: 1.45),
                ),
                if (reviewReason.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Review note: $reviewReason',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60, height: 1.4),
                  ),
                ],
                const SizedBox(height: 10),
                const Text(
                  'Identity and document checks need an authorized provider or recorded manual review. Training requirements and uploaded-document storage are not configured in this prototype.',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _statusLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        Text(
          value.replaceAll('_', ' ').toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF42D6B5),
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );

  String get _nextStep {
    if (accountStatus != 'active') {
      return 'This account is not active. Contact Trust Juggler support.';
    }
    if (registrationStatus == 'registration_pending') {
      return 'Your driver registration is pending server review.';
    }
    if (registrationStatus == 'rejected' || registrationStatus == 'suspended') {
      return 'Driver registration is $registrationStatus. Protected access remains unavailable.';
    }
    if (registrationStatus != 'approved') {
      return 'Driver registration has not been approved.';
    }
    if (identityStatus != 'verified') {
      return identityStatus == 'pending' || identityStatus == 'manual_review'
          ? 'Identity verification is pending review.'
          : 'Identity verification is not confirmed by the server.';
    }
    if (documentsStatus != 'verified') {
      return documentsStatus == 'pending' || documentsStatus == 'manual_review'
          ? 'Required document checks are pending review.'
          : 'Required document verification is not confirmed by the server.';
    }
    if (trainingStatus != 'complete') {
      return trainingStatus == 'pending' || trainingStatus == 'manual_review'
          ? 'Required training is pending review.'
          : 'Required training is not confirmed by the server.';
    }
    if (deviceStatus != 'enrolled') {
      return deviceStatus == 'pending_review'
          ? 'Device enrollment is pending server review.'
          : 'A device review must be completed before protected access.';
    }
    return 'Server status is incomplete. Protected access remains locked.';
  }
}

class _ModeBanner extends StatelessWidget {
  const _ModeBanner({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    color: const Color(0xFF141C30),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xFF42D6B5),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
      ),
    ),
  );
}
