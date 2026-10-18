# Trust Juggler local security model

## Stored data

The Flutter app includes Firebase Authentication support, but the risk demo has
no connected risk backend. The app stores no session credentials in its own
secure-storage namespace. `SecureStorageService` is a narrow, namespaced
facility for future session-only material; it deliberately rejects arbitrary
keys and does not persist an authenticated flag or biometric result. Session
state and timing metadata remain in memory only.

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

The Flutter project includes Firebase client options and Firebase
Authentication dependencies. The risk simulator added in this branch is
local-only and does not call Cloud Functions or Firestore. Client Firebase API
identifiers are not server credentials; never add service-account keys,
private keys, or privileged tokens to the app.

This repository has no Cloud Functions source package, Firestore rules, or
configured emulator suite. It therefore does not provide server-owned risk
state, admin claims, rate limits, audit records, or protected fleet actions.
The local simulation must not be used to make account decisions. Add these
backend controls before connecting real riders or telemetry.

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
- **Firebase account authentication** can verify account credentials when the
  supplied Firebase project is configured; it does not approve a rider.
- **Risk simulator** shows synthetic, in-memory state only and makes no remote
  authorization decision.

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

For this feature branch, `dart format` completed, `flutter analyze` reported no
issues, `flutter test` passed, and `flutter build apk --debug` succeeded. Install
the debug build on an attached device with:

```sh
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```
