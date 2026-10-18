import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/core/security/secure_storage_service.dart';
import 'package:rider_app/core/security/session_manager.dart';

class FakeBiometric implements BiometricGate {
  bool available = true;
  Future<bool> Function()? result;
  int calls = 0;
  @override
  Future<bool> canAuthenticate() async => available;
  @override
  Future<bool> authenticate() {
    calls++;
    return result?.call() ?? Future.value(true);
  }
}

class FakeStore implements SecureKeyValueStore {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read({required String key}) async {
    if (fail) throw StateError('private storage failure');
    return values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    if (fail) throw StateError('private storage failure');
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    if (fail) throw StateError('private storage failure');
    values.remove(key);
  }
}

class FakeClock implements SessionClock {
  DateTime current = DateTime.utc(2026);
  final events = <_Scheduled>[];
  @override
  DateTime now() => current;
  @override
  SessionCancellation schedule(Duration delay, VoidCallback callback) {
    final event = _Scheduled(current.add(delay), callback);
    events.add(event);
    return event;
  }

  void elapse(Duration duration) {
    current = current.add(duration);
    final due = events
        .where((e) => !e.cancelled && !e.at.isAfter(current))
        .toList();
    for (final event in due) {
      event.cancelled = true;
      event.callback();
    }
  }
}

class _Scheduled implements SessionCancellation {
  _Scheduled(this.at, this.callback);
  final DateTime at;
  final VoidCallback callback;
  bool cancelled = false;
  @override
  void cancel() => cancelled = true;
}

SessionManager makeManager({
  FakeBiometric? biometric,
  FakeStore? store,
  FakeClock? clock,
  SessionPolicy? policy,
}) => SessionManager(
  biometric: biometric ?? FakeBiometric(),
  secureStorage: SecureStorageService(store: store ?? FakeStore()),
  clock: clock ?? FakeClock(),
  policy:
      policy ??
      const SessionPolicy(
        inactivityTimeout: Duration(minutes: 2),
        maximumLifetime: Duration(minutes: 6),
      ),
);

void main() {
  test('successful biometric authentication unlocks the session', () async {
    final manager = makeManager();
    await manager.authenticate();
    expect(manager.state, SessionState.unlocked);
    manager.dispose();
  });

  test('failed and cancelled authentication stay locked', () async {
    final biometric = FakeBiometric()..result = () async => false;
    final manager = makeManager(biometric: biometric);
    await manager.authenticate();
    expect(manager.state, SessionState.locked);
    manager.dispose();
  });

  test('locked session requires a new biometric authentication', () async {
    final biometric = FakeBiometric();
    final manager = makeManager(biometric: biometric);
    await manager.authenticate();
    await manager.logout();
    expect(manager.state, SessionState.locked);
    await manager.authenticate();
    expect(manager.state, SessionState.unlocked);
    expect(biometric.calls, 2);
    manager.dispose();
  });

  test('inactivity expiry locks the session and clears session data', () async {
    final clock = FakeClock();
    final store = FakeStore()
      ..values['trust_juggler.session.ephemeral_session_material'] = 'sample';
    final manager = makeManager(clock: clock, store: store);
    await manager.authenticate();
    clock.elapse(const Duration(minutes: 2));
    await Future<void>.delayed(Duration.zero);
    expect(manager.state, SessionState.expired);
    expect(store.values, isEmpty);
    manager.dispose();
  });

  test(
    'meaningful activity resets idle expiry but not maximum lifetime',
    () async {
      final clock = FakeClock();
      final manager = makeManager(clock: clock);
      await manager.authenticate();
      clock.elapse(const Duration(minutes: 1));
      manager.recordMeaningfulActivity();
      clock.elapse(const Duration(minutes: 1));
      await Future<void>.delayed(Duration.zero);
      expect(manager.state, SessionState.unlocked);
      clock.elapse(const Duration(minutes: 1));
      await Future<void>.delayed(Duration.zero);
      expect(manager.state, SessionState.expired);
      manager.dispose();
    },
  );

  test('maximum lifetime expires despite regular activity', () async {
    final clock = FakeClock();
    final manager = makeManager(clock: clock);
    await manager.authenticate();
    for (var i = 0; i < 6; i++) {
      clock.elapse(const Duration(minutes: 1));
      manager.recordMeaningfulActivity();
    }
    await Future<void>.delayed(Duration.zero);
    expect(manager.state, SessionState.expired);
    manager.dispose();
  });

  test('logout clears in-memory session and persisted session data', () async {
    final store = FakeStore()
      ..values['trust_juggler.session.ephemeral_session_material'] = 'sample';
    final manager = makeManager(store: store);
    await manager.authenticate();
    await manager.logout();
    expect(manager.isUnlocked, isFalse);
    expect(store.values, isEmpty);
    manager.dispose();
  });

  test('storage failure fails safely and does not expose details', () async {
    final store = FakeStore()..fail = true;
    final manager = makeManager(store: store);
    await manager.authenticate();
    await manager.logout();
    expect(manager.state, SessionState.error);
    expect(manager.message, isNot(contains('private')));
    expect(manager.isUnlocked, isFalse);
    manager.dispose();
  });

  test('background policy locks or preserves session as configured', () async {
    final locking = makeManager();
    await locking.authenticate();
    await locking.onBackground();
    expect(locking.state, SessionState.locked);
    locking.dispose();

    final preserving = makeManager(
      policy: const SessionPolicy(lockOnBackground: false),
    );
    await preserving.authenticate();
    await preserving.onBackground();
    expect(preserving.state, SessionState.unlocked);
    preserving.dispose();
  });

  test(
    'new manager after restart starts locked without persisted auth flag',
    () async {
      final store = FakeStore()..values['authenticated'] = 'true';
      final manager = makeManager(store: store);
      expect(manager.state, SessionState.locked);
      expect(manager.isUnlocked, isFalse);
      manager.dispose();
    },
  );

  test(
    'duplicate requests are ignored and pending result cannot revive logout',
    () async {
      final completer = Completer<bool>();
      final biometric = FakeBiometric()..result = () => completer.future;
      final manager = makeManager(biometric: biometric);
      final first = manager.authenticate();
      await manager.authenticate();
      expect(biometric.calls, 1);
      await manager.logout();
      completer.complete(true);
      await first;
      expect(manager.isUnlocked, isFalse);
      manager.dispose();
    },
  );

  test('dispose cancels outstanding timers', () async {
    final clock = FakeClock();
    final manager = makeManager(clock: clock);
    await manager.authenticate();
    final timer = clock.events.single;
    manager.dispose();
    expect(timer.cancelled, isTrue);
  });
}
