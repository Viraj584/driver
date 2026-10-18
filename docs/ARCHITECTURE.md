# Architecture

## Current components

- Flutter app keeps its existing local biometric gate, Firebase Authentication setup, delivery preview, and driver screens.
- `lib/core/risk/risk_engine.dart` evaluates a typed demo event into a bounded score, reason codes, and verification recommendation. It has no Firebase or UI dependency.
- `lib/features/driver/risk_demo_screen.dart` holds synthetic session state in memory and presents repeatable simulator actions. Its simulated challenge is not a trusted identity check.
- Firebase client initialization is in `lib/core/auth/firebase_setup.dart`; credentials and sign-in are handled by existing auth gateways.

## Data flow and trust boundary

The current demo flow is UI action → pure local risk evaluator → in-memory display. There is no server call, Firestore persistence, authenticated risk evaluation, or administrator authorization in this repository. The demo's state transitions illustrate a flow and must not authorize a real shift or account restriction.

The intended connected flow is authenticated rider → validated telemetry callable → server risk evaluator → transactionally persisted session/rider/challenge/audit state → client reads authorized result. Administrator decisions must use verified Firebase custom claims and trusted server functions. Firestore client writes to privileged state should remain denied.
