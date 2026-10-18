# Trust Juggler rider prototype

Flutter prototype for rider session assurance and fleet risk demonstrations. The repository retains its existing delivery preview, local biometric gate, Firebase Authentication, and secure-storage code. A local deterministic risk simulation is available from the app's Risk Engine entry point.

## Run locally

```sh
flutter pub get
flutter run
```

Firebase client setup uses `lib/firebase_options.dart` and the platform configuration. A Firebase project may be used for account authentication, but this repository currently has no risk-engine Cloud Functions package or connected Firestore data flow. The risk dashboard is explicitly local demo data; it does not write to Firebase. Never add service account credentials to the app.

## Demo flow

Open **Risk Engine** from the app start screen. Try normal telemetry, device change, low-accuracy GPS jump, unusual speed, and possible handoff. A correlated handoff requests the simulated step-up check. The check is labeled as a demonstration and does not establish identity or liveness.

## Project notes

- [Implementation checklist](docs/IMPLEMENTATION_PLAN.md)
- [Architecture and trust boundaries](docs/ARCHITECTURE.md)
- [Risk model](docs/RISK_MODEL.md)
- [Security limitations](docs/SECURITY.md)

Run `flutter analyze` and `flutter test` for local checks. Firebase emulator and production setup are not part of this local simulation.
