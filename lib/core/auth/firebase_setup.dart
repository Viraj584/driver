import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../firebase_options.dart';

class FirebaseSetup {
  static const isDemoMode = bool.fromEnvironment('DEMO_MODE');
  static const _forceDevelopmentMode = bool.fromEnvironment(
    'TRUST_JUGGLER_FIREBASE_DISABLED',
  );
  static const _useEmulators = bool.fromEnvironment(
    'TRUST_JUGGLER_USE_FIREBASE_EMULATORS',
  );
  static const _emulatorHost = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );
  static bool _emulatorsConnected = false;

  static bool get isConfigured =>
      !isDemoMode && !_forceDevelopmentMode && Firebase.apps.isNotEmpty;

  static Future<void> initialize() async {
    if (isDemoMode || _forceDevelopmentMode) return;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    if (_useEmulators && !_emulatorsConnected) {
      await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
      FirebaseFunctions.instanceFor(region: 'us-central1')
          .useFunctionsEmulator(_emulatorHost, 5001);
      _emulatorsConnected = true;
    }
  }
}
