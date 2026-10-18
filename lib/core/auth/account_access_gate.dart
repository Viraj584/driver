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
    this.onDriverAccessGranted,
    this.adminAccess = false,
    this.onAdminAccessGranted,
    this.verifyAdminAccess,
    this.googleSignInAvailable,
    this.onPortalSelected,
    this.onRiskEngineSelected,
    this.demoMode = false,
    this.onDemoAccessGranted,
    super.key,
  });

  final bool firebaseConfigured;
  final Widget child;
  final AuthGateway? auth;
  final DriverBackendGateway? backend;
  final String? initializationError;
  final Future<void> Function()? beforeSignOut;
  final bool startInSignUp;

  /// Called only after Firebase identity and the trusted driver profile pass
  /// every existing protected-access requirement.
  final ValueChanged<User>? onDriverAccessGranted;
  final bool adminAccess;
  final ValueChanged<User>? onAdminAccessGranted;
  final Future<void> Function(User)? verifyAdminAccess;
  final bool? googleSignInAvailable;
  final VoidCallback? onPortalSelected;
  final VoidCallback? onRiskEngineSelected;
  final bool demoMode;
  final VoidCallback? onDemoAccessGranted;

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
  String _riskStatus = 'UNKNOWN';
  String _reviewReason = '';
  bool _isSignUp = false;
  final _phone = TextEditingController();
  final _smsCode = TextEditingController();
  final _email = TextEditingController();
  final _emailLinkAddress = TextEditingController();
  final _password = TextEditingController();
  final _emailLink = TextEditingController();
  Timer? _smsTimeoutTimer;
  Timer? _resendCooldownTimer;
  int _resendCooldownSeconds = 0;
  String? _redirectedDriverUid;
  bool _adminCheckInFlight = false;
  bool _adminVerified = false;
  String? _adminFailure;

  @override
  void initState() {
    super.initState();
    _isSignUp = widget.startInSignUp;
    _auth = widget.demoMode
        ? null
        : widget.auth ??
              (widget.firebaseConfigured
                  ? FirebaseAuthGateway(FirebaseAuth.instance)
                  : null);
    _backend = widget.demoMode ? null : widget.backend;
    if (_auth != null) {
      _user = _auth.currentUser;
      _observedUserUid = _user?.uid;
      _subscription = _auth.userChanges.listen(_onUserChanged);
      if (_user != null) {
        if (widget.adminAccess) {
          unawaited(_verifyAdmin(_user!));
        } else {
          unawaited(_bootstrapProfile(_user!));
        }
      }
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
      _redirectedDriverUid = null;
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
      _riskStatus = 'UNKNOWN';
      _adminVerified = false;
      _adminFailure = null;
      _adminCheckInFlight = false;
      _reviewReason = '';
      _message = '';
    });
    if (user != null) {
      if (widget.adminAccess) {
        await _verifyAdmin(user);
      } else {
        await _bootstrapProfile(user);
      }
    }
  }

  Future<void> _verifyAdmin(User user) async {
    if (_adminCheckInFlight || !widget.firebaseConfigured) return;
    _adminCheckInFlight = true;
    if (mounted) {
      setState(() {
        _adminFailure = null;
        _message = '';
      });
    }
    try {
      final verifier = widget.verifyAdminAccess;
      if (verifier != null) {
        await verifier(user);
      } else {
        await user.getIdToken(true);
        await FirebaseFunctions.instanceFor(region: driverFunctionsRegion)
            .httpsCallable('getFleetAuditHistory')
            .call();
      }
      if (!mounted || _user?.uid != user.uid) return;
      setState(() => _adminVerified = true);
      widget.onAdminAccessGranted?.call(user);
    } on FirebaseFunctionsException catch (error) {
      if (mounted && _user?.uid == user.uid) {
        setState(() {
          _adminFailure = error.code == 'permission-denied'
              ? 'This account is not authorized for Fleet Command.'
              : 'Fleet authorization could not be confirmed. Retry when the service is available.';
        });
      }
    } catch (_) {
      if (mounted && _user?.uid == user.uid) {
        setState(
          () => _adminFailure = 'Fleet authorization could not be confirmed. Retry when the service is available.',
        );
      }
    } finally {
      _adminCheckInFlight = false;
      if (mounted) setState(() {});
    }
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
          _riskStatus = profile.riskStatus;
          _reviewReason =
              profile.registrationStatusReason ??
              profile.identityVerificationStatusReason ??
              profile.requiredDocumentsStatusReason ??
              profile.trainingStatusReason ??
              '';
          _bootstrapped = true;
        });
        if (_driverEligible && _redirectedDriverUid != user.uid) {
          _redirectedDriverUid = user.uid;
          widget.onDriverAccessGranted?.call(user);
        }
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
    'invalid-action-code' => 'That sign-in link is invalid or expired.',
    'invalid-credential' =>
      'Email, password, phone code, or Google credential was not recognized.',
    'too-many-requests' =>
      'Too many attempts. Wait before requesting another code.',
    'invalid-phone-number' ||
    'invalid-email' => 'Check the phone number or email address.',
    'wrong-password' ||
    'user-not-found' ||
    'invalid-login-credentials' => 'Email or password was not recognized.',
    'email-already-in-use' =>
      'An account already uses this email. Log in instead.',
    'weak-password' => 'Choose a password with at least 8 characters.',
    'user-disabled' => 'This account is disabled. Contact support.',
    'network-request-failed' =>
      'Network error. Check your connection and retry.',
    'captcha-check-failed' ||
    'missing-client-identifier' ||
    'invalid-app-credential' => 'App verification could not be completed. Check Google Play services and retry; if it continues, contact support.',
    'app-not-authorized' =>
      'This app is not authorized for the configured Firebase project.',
    'operation-not-allowed' =>
      'This sign-in provider is disabled in Firebase Authentication settings.',
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
    _emailLinkAddress.dispose();
    _password.dispose();
    _emailLink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.demoMode) {
      return DemoDriverSignInPage(
        onContinue: widget.onDemoAccessGranted ?? () {},
        onPortalSelected: widget.onPortalSelected,
      );
    }
    if (widget.initializationError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFAF8FF),
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
      if (widget.adminAccess) {
        if (_adminVerified) return widget.child;
        return Scaffold(
          backgroundColor: const Color(0xFFFAF8FF),
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _adminFailure == null
                          ? Icons.admin_panel_settings_outlined
                          : Icons.lock_outline,
                      color: const Color(0xFF2563EB),
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _adminFailure ?? 'Verifying Fleet Command access…',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF131B2E)),
                    ),
                    if (_adminFailure == null) ...[
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(),
                    ],
                    if (_adminFailure != null) ...[
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: _busy || _adminCheckInFlight
                            ? null
                            : () => _verifyAdmin(_user!),
                        child: const Text('Retry authorization'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _perform(
                                () => _auth!.signOut(),
                                operation: 'adminSignOut',
                              ),
                        child: const Text('Sign out and use another account'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }
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
          backgroundColor: const Color(0xFFFAF8FF),
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
            color: Colors.white,
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
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'DEVICE ENROLLMENT: ${_deviceStatus.toUpperCase()} · Approval is server controlled.',
                      style: const TextStyle(
                        color: Color(0xFF434655),
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
            color: Colors.white,
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
                        controller: _emailLinkAddress,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email to link',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _perform(() async {
                                await _auth!.sendEmailLink(
                                  _emailLinkAddress.text.trim(),
                                );
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
                                    _emailLinkAddress.text.trim(),
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
                    riskStatus: _riskStatus,
                    reviewReason: _reviewReason,
                  ),
          ),
        ],
      );
    }
    return Theme(
      data: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFFAF8FF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFFAF8FF),
        bottomNavigationBar: NavigationBar(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFE9EEFF),
          selectedIndex: 1,
          onDestinationSelected: (index) {
            if (index == 0) widget.onPortalSelected?.call();
            if (index == 2) widget.onRiskEngineSelected?.call();
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.shield_outlined),
              label: 'Portal',
            ),
            NavigationDestination(
              icon: Icon(Icons.assignment_ind_outlined),
              label: 'Onboarding',
            ),
            NavigationDestination(
              icon: Icon(Icons.monitor_heart_outlined),
              label: 'Risk Engine',
            ),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        color: Color(0xFF2563EB),
                        size: 28,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TRUST JUGGLER',
                              style: TextStyle(
                                color: Color(0xFF131B2E),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                            Text(
                              'Driver onboarding',
                              style: TextStyle(
                                color: Color(0xFF434655),
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
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
                  const SizedBox(height: 14),
                  Card(
                    color: Colors.white,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFFC3C6D7)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.login, color: Color(0xFF2563EB)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _isSignUp
                                      ? 'Create your driver account'
                                      : 'Welcome back, Driver',
                                  style: const TextStyle(
                                    color: Color(0xFF131B2E),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed:
                                _busy ||
                                    _auth is! GoogleAuthGateway ||
                                    !(widget.googleSignInAvailable ??
                                        const String.fromEnvironment(
                                          'GOOGLE_SERVER_CLIENT_ID',
                                        ).isNotEmpty)
                                ? null
                                : () => _perform(
                                    () => (_auth as GoogleAuthGateway)
                                        .signInWithGoogle(),
                                    operation: 'googleAuthentication',
                                  ),
                            icon: const Icon(Icons.g_mobiledata),
                            label: Text(
                              !(widget.googleSignInAvailable ??
                                      const String.fromEnvironment(
                                        'GOOGLE_SERVER_CLIENT_ID',
                                      ).isNotEmpty)
                                  ? 'Google sign-in needs OAuth setup'
                                  : 'Continue with Google',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF131B2E),
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                const label = Text(
                                  'or continue with mobile number',
                                  style: TextStyle(
                                    color: Color(0xFF434655),
                                    fontSize: 12,
                                  ),
                                );
                                if (constraints.maxWidth < 360) {
                                  return const Center(child: label);
                                }
                                return const Row(
                                  children: [
                                    Expanded(child: Divider()),
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: label,
                                    ),
                                    Expanded(child: Divider()),
                                  ],
                                );
                              },
                            ),
                          ),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final phoneField = TextField(
                                controller: _phone,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'Registered Mobile Number',
                                  hintText: '+91 98765 43210',
                                  prefixIcon: Icon(Icons.phone_outlined),
                                  isDense: true,
                                  filled: true,
                                  fillColor: Color(0xFFF2F3FF),
                                  border: OutlineInputBorder(),
                                ),
                              );
                              final getOtp = FilledButton(
                                onPressed:
                                    _busy ||
                                        (_verificationId != null &&
                                            _resendCooldownSeconds > 0)
                                    ? null
                                    : () => _requestPhoneCode(
                                        operation: 'phoneCodeRequest',
                                      ),
                                child: Text(
                                  _busy
                                      ? 'Sending…'
                                      : _verificationId == null
                                      ? 'Get OTP'
                                      : _resendCooldownSeconds > 0
                                      ? 'Resend $_resendCooldownSeconds'
                                      : 'Get OTP again',
                                ),
                              );
                              if (constraints.maxWidth < 360) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    phoneField,
                                    const SizedBox(height: 8),
                                    getOtp,
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: phoneField),
                                  const SizedBox(width: 8),
                                  getOtp,
                                ],
                              );
                            },
                          ),
                          if (_verificationId != null) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: _smsCode,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              decoration: InputDecoration(
                                labelText: '6-Digit Verification Code',
                                counterText: '',
                                hintText: 'Enter OTP sent to SMS',
                                prefixIcon: Icon(Icons.pin_outlined),
                                isDense: true,
                                filled: true,
                                fillColor: Color(0xFFF2F3FF),
                                border: OutlineInputBorder(),
                                suffixIcon: TextButton(
                                  onPressed: _busy || _resendCooldownSeconds > 0
                                      ? null
                                      : () => _requestPhoneCode(
                                          operation: 'phoneCodeResend',
                                        ),
                                  child: Text('Resend'),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            key: const Key('verify-access-shift'),
                            onPressed: _busy || _verificationId == null
                                ? null
                                : () => _perform(
                                    () => _auth!.verifyPhoneCode(
                                      _verificationId!,
                                      normalizeSmsCode(_smsCode.text),
                                    ),
                                    operation: 'phoneCodeVerify',
                                  ),
                            icon: const Icon(Icons.verified_outlined),
                            label: Text(
                              _busy ? 'Verifying…' : 'Verify & Access Shift',
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              backgroundColor: const Color(0xFF2563EB),
                            ),
                          ),
                          const Divider(height: 28),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('Use email and password'),
                            children: [
                              TextField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [
                                  AutofillHints.username,
                                  AutofillHints.email,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Email address',
                                ),
                              ),
                              TextField(
                                controller: _password,
                                obscureText: true,
                                autofillHints: [
                                  _isSignUp
                                      ? AutofillHints.newPassword
                                      : AutofillHints.password,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                ),
                              ),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: _busy
                                    ? null
                                    : () => _perform(
                                        () async {
                                          final gateway = _auth;
                                          if (gateway is! PasswordAuthGateway) {
                                            throw StateError(
                                              'Email/password authentication is unavailable.',
                                            );
                                          }
                                          final passwordGateway =
                                              gateway as PasswordAuthGateway;
                                          if (_isSignUp) {
                                            await passwordGateway
                                                .createEmailPasswordAccount(
                                                  _email.text,
                                                  _password.text,
                                                );
                                          } else {
                                            await passwordGateway
                                                .signInWithEmailPassword(
                                                  _email.text,
                                                  _password.text,
                                                );
                                          }
                                        },
                                        operation:
                                            'emailPasswordAuthentication',
                                      ),
                                child: Text(
                                  _isSignUp
                                      ? 'Create account with email'
                                      : 'Log in with email',
                                ),
                              ),
                              TextField(
                                controller: _emailLinkAddress,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Email for sign-in link',
                                ),
                              ),
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _perform(() async {
                                        await _auth!.sendEmailLink(
                                          _emailLinkAddress.text.trim(),
                                        );
                                        if (mounted) {
                                          setState(() {
                                            _emailSent = true;
                                            _message = 'Sign-in link sent. Copy its full URL into the field below if this app did not open automatically.';
                                          });
                                        }
                                      }, operation: 'emailLinkRequest'),
                                child: const Text(
                                  'Send passwordless email link',
                                ),
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
                                            _emailLinkAddress.text.trim(),
                                            _emailLink.text.trim(),
                                          ),
                                          operation: 'emailLinkComplete',
                                        ),
                                  child: const Text('Complete email sign-in'),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _message,
                        style: const TextStyle(color: Color(0xFFBA1A1A)),
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
      ),
    );
  }

  bool get _driverEligible =>
      _accountStatus == 'active' &&
      _registrationStatus == 'approved' &&
      _identityStatus == 'verified' &&
      _documentsStatus == 'verified' &&
      _trainingStatus == 'complete' &&
      _deviceStatus == 'enrolled' &&
      _riskStatus == 'ACTIVE';
}

class DemoDriverSignInPage extends StatelessWidget {
  const DemoDriverSignInPage({
    required this.onContinue,
    this.onPortalSelected,
    super.key,
  });

  final VoidCallback onContinue;
  final VoidCallback? onPortalSelected;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAF8FF),
    appBar: AppBar(
      backgroundColor: const Color(0xFFFAF8FF),
      title: const Text('Driver sign in'),
      leading: IconButton(
        tooltip: 'Back to role selector',
        onPressed: onPortalSelected,
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _ModeBanner(text: 'LOCAL DEMO — NOT SYNCED TO FIREBASE'),
              const SizedBox(height: 24),
              const Text(
                'Demo driver access',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'This local session does not verify identity, send an SMS, or create a Firebase account.',
                style: TextStyle(color: Color(0xFF434655)),
              ),
              const SizedBox(height: 24),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.email_outlined),
                title: Text('virajb2005@gmail.com'),
                subtitle: Text('Demo display identity'),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.phone_outlined),
                title: Text('9371736836'),
                subtitle: Text('Demo display phone'),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onContinue,
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Continue as demo driver'),
              ),
              TextButton(
                onPressed: onPortalSelected,
                child: const Text('Back to role selector'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
    backgroundColor: const Color(0xFFFAF8FF),
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
                  color: Color(0xFF2563EB),
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
                  style: const TextStyle(color: Color(0xFF434655), height: 1.5),
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
    required this.riskStatus,
    required this.reviewReason,
  });

  final String accountStatus;
  final String registrationStatus;
  final String identityStatus;
  final String documentsStatus;
  final String trainingStatus;
  final String deviceStatus;
  final String riskStatus;
  final String reviewReason;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.assignment_outlined,
                  color: Color(0xFF2563EB),
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
                  style: TextStyle(color: Color(0xFF434655), height: 1.45),
                ),
                const SizedBox(height: 16),
                _statusLine('Account', accountStatus),
                _statusLine('Registration', registrationStatus),
                _statusLine('Identity verification', identityStatus),
                _statusLine('Required documents', documentsStatus),
                _statusLine('Required training', trainingStatus),
                _statusLine('Device enrollment', deviceStatus),
                _statusLine('Risk / step-up status', riskStatus),
                const SizedBox(height: 12),
                Text(
                  _nextStep,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF434655),
                    height: 1.45,
                  ),
                ),
                if (reviewReason.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Review note: $reviewReason',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF434655),
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                const Text(
                  'Identity and document checks need an authorized provider or recorded manual review. Training requirements and uploaded-document storage are not configured in this prototype.',
                  style: TextStyle(
                    color: Color(0xFF434655),
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
          child: Text(label, style: const TextStyle(color: Color(0xFF434655))),
        ),
        Text(
          value.replaceAll('_', ' ').toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF2563EB),
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );

  String get _nextStep {
    if (riskStatus == 'LIVENESS_PENDING') {
      return 'A server risk check requires additional verification. Protected access remains locked.';
    }
    if (riskStatus == 'RESTRICTED') {
      return 'This account is restricted by the server. Contact fleet support.';
    }
    if (riskStatus != 'ACTIVE') {
      return 'Server risk status could not be confirmed. Protected access remains locked.';
    }
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
    color: Colors.white,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xFF2563EB),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
      ),
    ),
  );
}
