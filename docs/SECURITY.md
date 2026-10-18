# Trust Juggler local security model

## Stored data

Firebase Auth owns account credentials and tokens. The Flutter app stores no
Firebase token, password, local authentication flag, or biometric result in its
own secure-storage namespace. `SecureStorageService` remains a narrow,
namespaced facility for future session-only material. Local session state and
timing metadata remain in memory only.

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

The app supports Firebase email/password, phone OTP, passwordless email link,
and Google OAuth credential sign-in. Firebase Console providers and OAuth
clients must be configured; failures stay failures. Google OAuth client IDs
passed as Dart defines are identifiers, not client secrets. Never put a service
account, private key, or privileged token in the app.

The risk callables require Firebase Auth. They accept a limited set of
synthetic event labels and compute scores on the server. Firestore client
reads/writes are denied; trusted callables use Admin SDK transactions to write
session results, rider state, challenges, and append-only audit records. Admin
fleet/history and review actions require the server-verified `admin` custom
claim. A simulated challenge result never clears or restricts the rider; it
marks review required. The functions and rules are implemented but have not
been deployed or verified against the configured Firebase project.

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
- **Local risk simulator** shows synthetic in-memory state when Firebase is
  explicitly disabled.
- **Server risk flow** stores synthetic event labels and server evaluations;
  it does not verify physical location, device integrity, SIM changes, face
  identity, or liveness.

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
Console provider setup, OAuth setup, emulator-backed integration testing, and
deployment remain outstanding. There is no DigiLocker, face liveness/matching,
device attestation, or authorized ride flow. Simulator event labels are
untrusted assertions and must not drive production fraud decisions.

## Checks

See the current branch's final validation report for command outcomes. Install
the debug build on an attached device with:

```sh
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```
