# Trust Juggler rider prototype

Flutter rider app with Firebase Authentication, local biometric quick unlock, and an authenticated Firebase risk-event flow. The risk screen can run deterministic local events when Firebase is explicitly disabled, or submit synthetic event labels to Cloud Functions when Firebase is configured and a user is signed in. The app does not treat a simulator event as verified device or location evidence.

## Run and verify

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

## Authentication setup

Enable **Email/Password** and **Phone** in Firebase Console → Authentication → Sign-in method, and configure authorized domains as needed. SMS sign-in requires the Android app registered in Firebase, current SHA-1 and SHA-256 signing fingerprints, Google Play services, and SMS quota/test-number setup. These are Firebase Console settings, not client-side shortcuts.

For Google sign-in, enable the Google provider. Set `GOOGLE_SERVER_CLIENT_ID` to the OAuth Web client ID for the same Firebase project using a Dart define, for example:

```sh
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=your-web-client-id.apps.googleusercontent.com
```

Android additionally needs the matching `google-services.json`, package name, and SHA fingerprints registered in Firebase. iOS needs the matching `GoogleService-Info.plist` and reversed client ID URL scheme in `ios/Runner/Info.plist`. OAuth consent screen and test-user settings must allow the account. Google sign-in stays unavailable if the server client ID is missing. The local biometric prompt only unlocks this device's app session; it does not sign into Firebase.

Email/password is the primary account path. It uses Firebase `signInWithEmailAndPassword` and `createUserWithEmailAndPassword`; wrong credentials and provider configuration errors remain failures. Firebase profile bootstrap still needs the Functions package deployed or emulator running.

## Local-only mode and emulators

To run without Firebase initialization:

```sh
flutter run --dart-define=TRUST_JUGGLER_FIREBASE_DISABLED=true
```

The risk screen will then display the local simulator. It never reports local events as persisted.

For the Functions/Auth emulator, install the Firebase CLI, then run:

```sh
npm ci --prefix functions
firebase emulators:start --only auth,functions,firestore
```

On Android Emulator use `FIREBASE_EMULATOR_HOST=10.0.2.2` and run:

```sh
flutter run \
  --dart-define=TRUST_JUGGLER_USE_FIREBASE_EMULATORS=true \
  --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2
```

For iOS Simulator or desktop, use `127.0.0.1`. Email/password authentication and callables are directed to emulators when the flag is enabled. Set up an emulator user through the Auth Emulator UI or CLI. Google provider sign-in should be tested against Firebase with a configured OAuth client, not assumed to work through the emulator.

Build/test backend code without deployment:

```sh
npm run build --prefix functions
npm test --prefix functions
```

No Firebase resources are deployed by these commands. Deployment requires project access and review; use `firebase deploy --only functions,firestore:rules,firestore:indexes` only in an explicitly selected development project.

## Existing app features

The existing driver journey previews, earnings screens, Firebase phone/email-link flows, secure storage, and local biometric session gate remain in place. See [architecture](docs/ARCHITECTURE.md), [risk model](docs/RISK_MODEL.md), [security](docs/SECURITY.md), and [implementation checklist](docs/IMPLEMENTATION_PLAN.md).
