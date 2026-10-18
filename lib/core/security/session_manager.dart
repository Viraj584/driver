import 'dart:async';

import 'package:flutter/foundation.dart';

import 'secure_storage_service.dart';

enum SessionState {
  locked,
  authenticating,
  unlocked,
  expired,
  loggingOut,
  error,
}

abstract interface class BiometricGate {
  Future<bool> canAuthenticate();
  Future<bool> authenticate();
}

class SessionPolicy {
  const SessionPolicy({
    this.inactivityTimeout = const Duration(minutes: 5),
    this.maximumLifetime = const Duration(hours: 8),
    this.lockOnBackground = true,
  });

  final Duration inactivityTimeout;
  final Duration maximumLifetime;
  final bool lockOnBackground;
}

abstract interface class SessionClock {
  DateTime now();
  SessionCancellation schedule(Duration delay, VoidCallback callback);
}

abstract interface class SessionCancellation {
  void cancel();
}

class SystemSessionClock implements SessionClock {
  SystemSessionClock()
    : _origin = DateTime.now(),
      _stopwatch = Stopwatch()..start();

  final DateTime _origin;
  final Stopwatch _stopwatch;

  @override
  DateTime now() => _origin.add(_stopwatch.elapsed);

  @override
  SessionCancellation schedule(Duration delay, VoidCallback callback) =>
      _TimerCancellation(Timer(delay, callback));
}

class _TimerCancellation implements SessionCancellation {
  _TimerCancellation(this.timer);
  final Timer timer;

  @override
  void cancel() => timer.cancel();
}

class SessionManager extends ChangeNotifier {
  SessionManager({
    required this.biometric,
    required this.secureStorage,
    this.policy = const SessionPolicy(),
    SessionClock? clock,
  }) : clock = clock ?? SystemSessionClock() {
    if (policy.inactivityTimeout <= Duration.zero ||
        policy.maximumLifetime <= Duration.zero) {
      throw ArgumentError('Session timeouts must be positive.');
    }
  }

  final BiometricGate biometric;
  final SecureStorageService secureStorage;
  final SessionClock clock;
  final SessionPolicy policy;

  SessionState state = SessionState.locked;
  String message = 'Verify your identity to secure this session.';
  DateTime? _unlockedAt;
  DateTime? _lastActivityAt;
  SessionCancellation? _expiryTimer;
  int _operation = 0;
  bool _authInFlight = false;
  bool _disposed = false;

  bool get isUnlocked => state == SessionState.unlocked;

  Future<void> authenticate() async {
    if (_disposed ||
        _authInFlight ||
        state == SessionState.loggingOut ||
        isUnlocked) {
      return;
    }
    _authInFlight = true;
    final operation = ++_operation;
    _setState(
      SessionState.authenticating,
      'Checking device biometric availability...',
    );
    try {
      if (!await biometric.canAuthenticate()) {
        if (_isCurrent(operation)) {
          _setState(
            SessionState.error,
            'No enrolled biometric is available. Access remains locked. Set up fingerprint or face authentication in Android Settings, then retry.',
          );
        }
        return;
      }
      final success = await biometric.authenticate();
      if (!_isCurrent(operation)) return;
      if (!success) {
        _setState(
          SessionState.locked,
          'Verification was cancelled or not completed.',
        );
        return;
      }
      final now = clock.now();
      _unlockedAt = now;
      _lastActivityAt = now;
      _setState(
        SessionState.unlocked,
        'Device biometric authentication succeeded.',
      );
      _scheduleExpiry();
    } catch (_) {
      if (_isCurrent(operation)) {
        _setState(
          SessionState.error,
          'Biometric verification failed. No session was unlocked. Check fingerprint or face setup in Android Settings and retry.',
        );
      }
    } finally {
      _authInFlight = false;
    }
  }

  /// Called only for user interaction with protected content.
  void recordMeaningfulActivity() {
    if (!isUnlocked || _disposed) return;
    final now = clock.now();
    final unlockedAt = _unlockedAt;
    final previousActivity = _lastActivityAt;
    if (unlockedAt == null || previousActivity == null) {
      unawaited(_expire());
      return;
    }
    if (now.difference(unlockedAt) >= policy.maximumLifetime ||
        now.difference(previousActivity) >= policy.inactivityTimeout) {
      unawaited(_expire());
      return;
    }
    _lastActivityAt = now;
    _scheduleExpiry();
  }

  Future<void> onBackground() async {
    if (policy.lockOnBackground &&
        (isUnlocked || state == SessionState.authenticating)) {
      await logout();
    }
  }

  Future<void> logout() async {
    if (_disposed || state == SessionState.loggingOut) return;
    ++_operation; // Invalidates any outstanding authentication result.
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _unlockedAt = null;
    _lastActivityAt = null;
    _setState(SessionState.loggingOut, 'Locking session...');
    try {
      await secureStorage.clearSessionData();
      if (!_disposed) {
        _setState(
          SessionState.locked,
          'Session locked. Verify your identity to continue.',
        );
      }
    } catch (_) {
      if (!_disposed) {
        _setState(
          SessionState.error,
          'Session access was cleared, but secure storage cleanup failed. Restart and try again.',
        );
      }
    }
  }

  Future<void> _expire() async {
    if (!isUnlocked) return;
    ++_operation;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _unlockedAt = null;
    _lastActivityAt = null;
    _setState(SessionState.loggingOut, 'Session expired. Locking session...');
    try {
      await secureStorage.clearSessionData();
      if (!_disposed) {
        _setState(
          SessionState.expired,
          'Session expired. Verify your identity to continue.',
        );
      }
    } catch (_) {
      if (!_disposed) {
        _setState(
          SessionState.error,
          'Session expired, but secure storage cleanup failed. Access remains locked.',
        );
      }
    }
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final unlockedAt = _unlockedAt;
    final lastActivityAt = _lastActivityAt;
    if (unlockedAt == null || lastActivityAt == null) return;
    final now = clock.now();
    final inactiveIn =
        policy.inactivityTimeout - now.difference(lastActivityAt);
    final lifetimeIn = policy.maximumLifetime - now.difference(unlockedAt);
    final delay = inactiveIn < lifetimeIn ? inactiveIn : lifetimeIn;
    _expiryTimer = clock.schedule(delay, () {
      if (!isUnlocked) return;
      final current = clock.now();
      final idleExpired =
          current.difference(_lastActivityAt!) >= policy.inactivityTimeout;
      final lifetimeExpired =
          current.difference(_unlockedAt!) >= policy.maximumLifetime;
      if (idleExpired || lifetimeExpired) {
        unawaited(_expire());
      } else {
        _scheduleExpiry();
      }
    });
  }

  bool _isCurrent(int operation) => !_disposed && operation == _operation;

  void _setState(SessionState next, String nextMessage) {
    if (_disposed) return;
    state = next;
    message = nextMessage;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_operation;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _unlockedAt = null;
    _lastActivityAt = null;
    state = SessionState.locked;
    super.dispose();
  }
}
