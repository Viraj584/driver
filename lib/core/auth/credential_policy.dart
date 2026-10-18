enum CredentialUse { signIn, link }

/// Accepts an international number and normalizes display separators only.
/// A country code is never guessed or prepended for a national number.
String normalizeE164PhoneNumber(String input) {
  var value = input.trim().replaceAll(RegExp(r'[\s().-]'), '');
  if (value.startsWith('00')) value = '+${value.substring(2)}';
  if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value)) {
    throw const FormatException(
      'Enter an international phone number with country code, such as +91XXXXXXXXXX.',
    );
  }
  return value;
}

/// Trims surrounding whitespace while preserving every SMS digit, including
/// leading zeroes.
String normalizeSmsCode(String input) {
  final value = input.trim();
  if (!RegExp(r'^[0-9]{4,8}$').hasMatch(value)) {
    throw const FormatException('Enter the SMS code using its digits only.');
  }
  return value;
}

/// Serializes automatic and manually entered phone credential completion.
class CredentialOperationCoordinator {
  Future<void>? _active;

  Future<void> run(Future<void> Function() operation) async {
    final active = _active;
    if (active != null) return active;
    final future = operation();
    _active = future;
    try {
      await future;
    } finally {
      if (identical(_active, future)) _active = null;
    }
  }
}

/// Never attaches a credential to a different user than the one that started
/// the verification flow, and never silently switches signed-in identities.
CredentialUse decideCredentialUse({
  required String? initiatingUid,
  required String? currentUid,
}) {
  if (initiatingUid == null && currentUid == null) {
    return CredentialUse.signIn;
  }
  if (initiatingUid != null && initiatingUid == currentUid) {
    return CredentialUse.link;
  }
  throw StateError('The signed-in account changed during verification.');
}
