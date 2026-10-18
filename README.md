# Trust Juggler Rider App

Flutter driver client with a biometric-gated local session and optional Firebase
account authentication. With no Firebase client identifiers configured, it
shows a visible Development Mode label and only runs the local prototype.

See [`../docs/phase-1-foundation.md`](../docs/phase-1-foundation.md) for Firebase
configuration, Android Phone Auth setup, email-link setup, callable functions,
deployment and security limitations.

Run `flutter analyze`, `flutter test`, and `flutter build apk --debug` from this
directory. Firebase's phone and email flows require an actual configured
project; widget tests use injected auth/backend abstractions.
