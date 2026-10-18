# Trust Juggler local security model

## Stored data

There is currently no user identity, backend, access token, password, or other
application secret in this prototype. Consequently, the app stores no session
credentials. `SecureStorageService` is a narrow, namespaced facility for future
session-only material; it deliberately rejects arbitrary keys and does not
persist an authenticated flag or biometric result. Session state and timing
metadata remain in memory only.

On Android, the service uses `flutter_secure_storage` with its current default
RSA OAEP plus AES GCM encryption implementation and migration backup enabled.
The package stores encrypted values and a wrapped AES data key in preferences;
the RSA private key is held through Android Keystore. `resetOnError` is disabled
so an Android storage error is surfaced rather than silently deleting data and
reporting a reset as success. No biometric storage option is enabled: Android
`local_auth` remains the only biometric gate.

`android:allowBackup="false"` is set, with explicit exclusions for the package's
data, wrapped-key, and configuration preferences in both legacy backup rules and
Android 12+ cloud-backup and device-transfer rules. Android documents that some
manufacturers may still perform device-to-device transfer despite
`allowBackup="false"`; the device-transfer exclusions address that path. The
settings should still be verified on target device/OEM combinations.

## Session lifecycle

The app begins locked after every process start. Biometric authentication moves
the local session through `locked -> authenticating -> unlocked` only when the
platform returns success. Cancellation or a false result returns it to locked;
availability checks and exceptions fail closed. Explicit logout, backgrounding
(the default policy), five minutes without meaningful protected-content input,
or eight hours of total lifetime revoke in-memory access and clear namespaced
session data. The inactivity and maximum-lifetime defaults live in
`SessionPolicy`; the screen can inject a different policy.

Meaningful activity is recorded from interaction with the protected session
area. Timer callbacks and rebuilds do not reset inactivity. The manager cancels
timers during logout, expiry, and disposal, and ignores late biometric results
after logout.

## Firebase account and backend boundary

When Firebase client identifiers are configured at build time, the app uses
Firebase Authentication for SMS phone verification and passwordless email-link
sign-in. Email link is an officially supported Firebase passwordless method;
it is not a numeric email OTP. Verified phone/email credentials can be linked
to the currently signed-in UID. If the UID changes while verification is
pending, the link/sign-in attempt fails closed. The app does not merge Firebase
accounts automatically. If Firebase is not configured, the app visibly labels
the experience Development Mode and only uses the local biometric demo. A
configured Firebase initialization failure fails closed.

After sign-in, authenticated callable functions bootstrap a driver record with
`registration_pending` and `identity_pending` server-side states. Device
enrollment requests remain `pending_review`; a server custom admin claim is
required to approve/revoke replacement records. Firestore client rules deny all
direct reads and writes. Rate limits and audit events are implemented in the
callables. App Check, admin web UI and emulator-backed integration tests are
not yet configured.

Ride start remains denied because no provider-backed face/liveness event is
available. A successful account sign-in or local biometric check does not mark
a driver approved, prove device integrity or authorize a ride.

## What each control means

- **Biometric authentication** asks Android to verify a local device biometric.
  It does not identify a Trust Juggler account or prove device integrity.
- **Local session state** is a Flutter in-memory gate for this prototype's
  protected UI. It is not a hardware-backed authorization boundary.
- **Secure persistence** encrypts explicitly permitted local values with
  platform storage facilities. No such sensitive application value exists yet.
- **Firebase account authentication** verifies a phone number or email-link
  ownership with Firebase when configured; it does not approve driver
  registration.
- **Callable authorization** verifies Firebase Authentication context and
  server-owned role/status/device records. Ride authorization remains closed.

Logout and expiry clear the manager's in-memory session timestamps and delete
all keys in the service's session namespace. Storage errors are shown without
including exception contents, and access remains locked. Fingerprints,
templates, and reusable biometric results are never stored. Firebase Auth may
restore its own signed-in account state after process restart; the local
`SessionManager` still starts locked and requires a fresh biometric result
before showing its protected session. The app does not copy Firebase tokens
into the secure-storage session namespace. Firebase account sign-out first
clears the local session and then calls the Firebase Auth SDK's `signOut()`.

## Limitations

This is prototype-grade local session and backend foundation work, not a
security assessment or compliance claim. Flutter booleans, timers, and
timestamps are not hardware-backed security. Secure storage and biometric-
gated UI do not protect against rooted or compromised devices, malicious
processes, instrumentation, or operating-system vulnerabilities. Firebase
configuration and deployment are outstanding. There is no DigiLocker, face
liveness/matching, device attestation, production admin console, or authorized
ride flow.

## Checks

Run `flutter pub get`, `dart format .`, `flutter analyze`, `flutter test`, and
`flutter build apk --debug`. Install the debug build on an attached device with:

```sh
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```
