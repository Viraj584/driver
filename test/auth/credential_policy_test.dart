import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/core/auth/credential_policy.dart';

void main() {
  test('overlapping automatic and manual completion runs once', () async {
    final coordinator = CredentialOperationCoordinator();
    final gate = Completer<void>();
    var operations = 0;
    final automatic = coordinator.run(() async {
      operations++;
      await gate.future;
    });
    final manual = coordinator.run(() async {
      operations++;
    });
    expect(operations, 1);
    gate.complete();
    await Future.wait([automatic, manual]);
    expect(operations, 1);
  });

  test('phone normalization preserves international country codes', () {
    expect(normalizeE164PhoneNumber(' +91 (98765) 43210 '), '+919876543210');
    expect(normalizeE164PhoneNumber('00919876543210'), '+919876543210');
    expect(() => normalizeE164PhoneNumber('9876543210'), throwsFormatException);
    expect(
      () => normalizeE164PhoneNumber('+01234567890'),
      throwsFormatException,
    );
  });

  test('SMS validation trims whitespace and preserves leading zeroes', () {
    expect(normalizeSmsCode(' 001234 '), '001234');
    expect(() => normalizeSmsCode('12 34'), throwsFormatException);
    expect(() => normalizeSmsCode(''), throwsFormatException);
  });

  test(
    'new credential signs in only if no account changed during verification',
    () {
      expect(
        decideCredentialUse(initiatingUid: null, currentUid: null),
        CredentialUse.signIn,
      );
      expect(
        () => decideCredentialUse(
          initiatingUid: null,
          currentUid: 'another-user',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'credential links only to the exact account that began verification',
    () {
      expect(
        decideCredentialUse(
          initiatingUid: 'same-user',
          currentUid: 'same-user',
        ),
        CredentialUse.link,
      );
      expect(
        () => decideCredentialUse(
          initiatingUid: 'original-user',
          currentUid: 'different-user',
        ),
        throwsStateError,
      );
      expect(
        () => decideCredentialUse(
          initiatingUid: 'original-user',
          currentUid: null,
        ),
        throwsStateError,
      );
    },
  );
}
