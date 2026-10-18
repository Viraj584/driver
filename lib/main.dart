import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'core/auth/account_access_gate.dart';
import 'core/auth/firebase_setup.dart';
import 'core/security/secure_storage_service.dart';
import 'core/security/security_diagnostics.dart';
import 'core/security/session_manager.dart';
import 'features/driver/stitch_screens.dart';
import 'features/driver/driver_journey_screens.dart';
import 'features/driver/driver_earnings_screen.dart';
import 'features/driver/risk_demo_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? initializationError;
  try {
    await FirebaseSetup.initialize();
  } on FirebaseException catch (error) {
    initializationError = error.code;
    SecurityDiagnostics.failure(
      operation: 'firebaseInitialize',
      correlationId: SecurityDiagnostics.newCorrelationId(),
      exceptionCode: error.code,
    );
  } catch (_) {
    initializationError = 'unknown error';
    SecurityDiagnostics.failure(
      operation: 'firebaseInitialize',
      correlationId: SecurityDiagnostics.newCorrelationId(),
      exceptionCode: 'unexpected-initialization-error',
    );
  }
  runApp(
    TrustJugglerApp(
      firebaseConfigured: FirebaseSetup.isConfigured,
      initializationError: initializationError,
    ),
  );
}

class LocalBiometricAuthenticator implements BiometricGate {
  LocalBiometricAuthenticator([LocalAuthentication? authentication])
    : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;

  @override
  Future<bool> canAuthenticate() async {
    final supported = await _authentication.isDeviceSupported();
    final biometrics = await _authentication.getAvailableBiometrics();
    return supported && biometrics.isNotEmpty;
  }

  @override
  Future<bool> authenticate() => _authentication.authenticate(
    localizedReason:
        'Verify your identity to continue your Trust Juggler session.',
    biometricOnly: true,
    persistAcrossBackgrounding: true,
  );
}

class TrustJugglerApp extends StatefulWidget {
  const TrustJugglerApp({
    this.firebaseConfigured = false,
    this.initializationError,
    this.sessionManager,
    super.key,
  });

  final bool firebaseConfigured;
  final String? initializationError;
  final SessionManager? sessionManager;

  @override
  State<TrustJugglerApp> createState() => _TrustJugglerAppState();
}

class _TrustJugglerAppState extends State<TrustJugglerApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final SessionManager _session;
  late final bool _ownsSession;

  @override
  void initState() {
    super.initState();
    _ownsSession = widget.sessionManager == null;
    _session =
        widget.sessionManager ??
        SessionManager(
          biometric: LocalBiometricAuthenticator(),
          secureStorage: SecureStorageService(
            store: FlutterSecureKeyValueStore(),
          ),
        );
  }

  @override
  void dispose() {
    if (_ownsSession) _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Trust Juggler',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1020),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF42D6B5),
          brightness: Brightness.dark,
        ),
      ),
      home: TrustJugglerRoleSelector(
        onDriverAuth: _openDriverAuth,
        onOnboarding: () => _openDriverAuth(signUp: true),
        onFleetAccess: _openFleetAccess,
        onRiskEngine: _openRiskEngine,
      ),
    );
  }

  void _openDriverAuth({bool signUp = false}) {
    _navigatorKey.currentState
        ?.push(
          MaterialPageRoute<void>(
            builder: (_) => AccountAccessGate(
              firebaseConfigured: widget.firebaseConfigured,
              initializationError: widget.initializationError,
              startInSignUp: signUp,
              beforeSignOut: _session.logout,
              child: RiderVerificationScreen(sessionManager: _session),
            ),
          ),
        )
        .whenComplete(() => unawaited(_session.logout()));
  }

  void _openFleetAccess() {
    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => const FleetAccessUnavailableScreen(),
      ),
    );
  }

  void _openRiskEngine() {
    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => const RiskDemoScreen()),
    );
  }
}

class RiderVerificationScreen extends StatefulWidget {
  const RiderVerificationScreen({
    super.key,
    this.authenticator,
    this.secureStorage,
    this.sessionManager,
    this.sessionPolicy = const SessionPolicy(),
  });

  final BiometricGate? authenticator;
  final SecureStorageService? secureStorage;
  final SessionManager? sessionManager;
  final SessionPolicy sessionPolicy;

  @override
  State<RiderVerificationScreen> createState() =>
      _RiderVerificationScreenState();
}

class _RiderVerificationScreenState extends State<RiderVerificationScreen>
    with WidgetsBindingObserver {
  late final SessionManager _session;
  late final bool _ownsSession;

  bool get _busy =>
      _session.state == SessionState.authenticating ||
      _session.state == SessionState.loggingOut;
  bool get _verified => _session.isUnlocked;

  @override
  void initState() {
    super.initState();
    _ownsSession = widget.sessionManager == null;
    _session =
        widget.sessionManager ??
        SessionManager(
          biometric: widget.authenticator ?? LocalBiometricAuthenticator(),
          secureStorage:
              widget.secureStorage ??
              SecureStorageService(store: FlutterSecureKeyValueStore()),
          policy: widget.sessionPolicy,
        );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsSession) _session.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(_session.onBackground());
    }
  }

  void _logout() {
    unawaited(_session.logout());
  }

  void _openDispatchPreview(DriverOrderSummary order) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DispatchConfirmationScreen(
          order: order,
          onPreviewCompletion: () => _openCompletionPreview(order),
        ),
      ),
    );
  }

  void _openCompletionPreview(DriverOrderSummary order) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeliveryCompletionScreen(
          order: order,
          onPreviewPayout: () => _openPayoutPreview(order),
        ),
      ),
    );
  }

  void _openPayoutPreview(DriverOrderSummary order) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DriverPayoutScreen(order: order)),
    );
  }

  void _openEarnings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DriverEarningsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF2563EB);

    return Theme(
      data: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFFAF8FF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.light,
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: const Color(0xFF131B2E),
          displayColor: const Color(0xFF131B2E),
        ),
      ),
      child: AnimatedBuilder(
        animation: _session,
        builder: (context, _) => Scaffold(
          backgroundColor: const Color(0xFFFAF8FF),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.shield_outlined,
                              color: accent,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TRUST JUGGLER',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              Text(
                                'RIDER SECURITY',
                                style: TextStyle(
                                  color: Color(0xFF434655),
                                  fontSize: 11,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 54),
                      Text(
                        'Biometric access',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Use a device biometric to unlock your local app session. This does not verify your identity with Trust Juggler.',
                        style: TextStyle(
                          color: Color(0xFF434655),
                          height: 1.6,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 38),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 34,
                          horizontal: 22,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFC3C6D7)),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 112,
                              height: 112,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: accent.withValues(alpha: 0.09),
                                border: Border.all(
                                  color: accent.withValues(alpha: 0.35),
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                _verified
                                    ? Icons.verified_user_outlined
                                    : Icons.fingerprint,
                                size: 68,
                                color: accent,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _verified
                                  ? 'Local session unlocked'
                                  : 'Biometric check',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _session.message,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF434655),
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 28),
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: FilledButton.icon(
                                onPressed: _busy || _verified
                                    ? null
                                    : _session.authenticate,
                                icon: Icon(
                                  _busy
                                      ? Icons.hourglass_top
                                      : Icons.fingerprint,
                                ),
                                label: Text(
                                  _busy
                                      ? 'Checking...'
                                      : _verified
                                      ? 'Session unlocked'
                                      : 'Verify with biometrics',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: Colors.white,
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_verified) ...[
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (_) => _session.recordMeaningfulActivity(),
                          child: Container(
                            key: const Key('protected-session'),
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFA7F3D0),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'PROTECTED SESSION',
                                  style: TextStyle(
                                    color: Color(0xFF006C49),
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Your local app session is unlocked.',
                                  style: TextStyle(color: Color(0xFF131B2E)),
                                ),
                                DriverDeliveryPoolScreen(
                                  onPreviewDispatch: _openDispatchPreview,
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  key: const Key('open-driver-earnings'),
                                  onPressed: _openEarnings,
                                  icon: const Icon(
                                    Icons.account_balance_wallet_outlined,
                                  ),
                                  label: const Text(
                                    'View earnings and payouts',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  key: const Key('logout-button'),
                                  onPressed: _logout,
                                  icon: const Icon(Icons.lock_outline),
                                  label: const Text('Lock session'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            color: Color(0xFF64748B),
                            size: 19,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Biometric matching is handled by Android. '
                              'This prototype does not collect or store '
                              'fingerprint images or templates.',
                              style: TextStyle(
                                color: Color(0xFF475569),
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
