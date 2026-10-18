# Implementation checklist

## Completed in this branch

- [x] Audit Flutter repository, Firebase setup, current screens, dependencies, and existing tests.
- [x] Inspect the adjacent Stitch design reference (`../dashboard/DESIGN.md`, `../dashboard/code.html`, and `../dashboard/screen.png`); use its compact light surfaces, fine borders, and restrained signal color in the new screen.
- [x] Create feature branch `feat/trust-juggler-risk-engine`.
- [x] Add a pure deterministic Dart risk evaluator and focused unit tests.
- [x] Replace the Risk Engine placeholder route with a local rider risk simulator and step-up demonstration.
- [x] Document architecture, model, security boundary, and setup.
- [x] Verify `dart format`, `flutter analyze`, `flutter test`, and `flutter build apk --debug` locally.

## Remaining before a connected prototype

- [ ] Implement authenticated server functions and Firestore-backed rider/session/challenge/audit records in this repository.
- [ ] Add Firestore rules and Auth/Functions/Firestore emulator integration tests.
- [ ] Connect the Flutter simulation interface to the server adapter and add offline/error states for remote operations.
- [ ] Build an authorized fleet dashboard with review actions and audit history.
- [ ] Add production-grade role provisioning, App Check, monitoring, and deployment review.

No Firebase resources were deployed. No remote integration is claimed for the demo screen.
