# Implementation checklist

## Completed in this branch

- [x] Audit Flutter repository, Firebase setup, current screens, dependencies, and existing tests.
- [x] Inspect the adjacent Stitch design reference (`../../dashboard/DESIGN.md`, `../../dashboard/code.html`, and `../../dashboard/screen.png`); use its compact light surfaces, fine borders, and restrained signal color in the new screen.
- [x] Create feature branch `feat/trust-juggler-risk-engine`.
- [x] Add a pure deterministic Dart risk evaluator and focused unit tests.
- [x] Replace the Risk Engine placeholder route with a local rider risk simulator and step-up demonstration.
- [x] Add Firebase email/password registration and sign-in, Google OAuth credential exchange, preserve phone OTP/email-link, and keep biometric unlock local-only.
- [x] Add authenticated, validated Firebase risk callables with server-side scoring, idempotency, transactional event/rider/challenge/audit writes, history queries, admin-only review, and deny-by-default Firestore rules.
- [x] Connect the configured simulator to callable event submission and server history; show an explicit local-only fallback when Firebase is disabled.
- [x] Add Firebase Auth/Functions emulator wiring and risk-policy unit tests.
- [x] Document architecture, model, security boundary, and setup.
- [x] Verify `dart format`, `flutter analyze`, `flutter test`, and `flutter build apk --debug` locally.

## Remaining before a production-connected prototype

- [ ] Enable and test Firebase email/password, SMS OTP, and Google providers in Firebase Console; set Android signing fingerprints and iOS URL schemes.
- [ ] Run callable and rules integration tests against Auth/Functions/Firestore emulators.
- [ ] Provision custom admin claims through a trusted audited process.
- [ ] Configure App Check, monitoring, alerting, and review deployment in a non-production Firebase project.
- [ ] Configure a real identity/liveness provider before treating verification outcomes as identity evidence.

No Firebase resources were deployed. The callable integration is implemented but not verified against a live project. Event labels are synthetic and untrusted.

## Validation results

- `flutter pub get`: passed.
- `flutter analyze`: passed with no issues.
- `flutter test`: passed (80 tests).
- `flutter build apk --debug`: passed.
- `npm run build --prefix functions`: passed under Node 22.23.3.
- `npm test --prefix functions`: passed (11 tests) under Node 22.23.3.
- Auth/Functions/Firestore emulator integration and rules tests were not run; this environment has no Java runtime for the Firebase emulators.
