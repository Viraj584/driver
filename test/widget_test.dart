import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/main.dart';
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
