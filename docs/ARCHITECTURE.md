# Architecture

## Current components

- Flutter app keeps its existing local biometric gate, Firebase Authentication setup, delivery preview, and driver screens.
- `lib/core/risk/risk_engine.dart` evaluates a typed demo event into a bounded score, reason codes, and verification recommendation. It has no Firebase or UI dependency.
- `lib/features/driver/risk_demo_screen.dart` holds synthetic session state in memory and presents repeatable simulator actions. Its simulated challenge is not a trusted identity check.
- Firebase client initialization is in `lib/core/auth/firebase_setup.dart`; credentials and sign-in are handled by existing auth gateways.
- Firebase Auth also supports email/password credentials, Google ID-token exchange, phone OTP, and email-link flows. `local_auth` remains a local unlock gate, not an account identity provider.
- `functions/src/risk-flow.ts` exposes authenticated callable operations. `risk-policy.ts` maps validated demonstration event labels to the bounded risk policy.

## Data flow and trust boundary

With Firebase disabled, the demo flow is UI action → pure local evaluator → in-memory display. With Firebase configured and a signed-in account, it is UI action → authenticated callable → allowlisted event validation → server-side evaluation → Firestore transaction writing session event, rider state, challenge (when required), and append-only audit record → callable history → dashboard. Request IDs make event retries idempotent. Server received timestamps are used; raw location, SIM, and device identifiers are not accepted.

Event labels originate from the simulator and are not independently verified telemetry. A demo challenge result is marked simulated, requires review, and cannot change the rider's pending state. Fleet history, audit history, approval, and restriction callables require the Firebase `admin: true` custom claim. Administrative state changes require a reason and append an audit record. Firestore client reads and writes are denied; trusted functions use Admin SDK access.
