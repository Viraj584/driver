import 'package:firebase_core/firebase_core.dart';

import '../../firebase_options.dart';

class FirebaseSetup {
  static bool get isConfigured => Firebase.apps.isNotEmpty;

  static Future<void> initialize() async {
    if (Firebase.apps.isNotEmpty) return;

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}
