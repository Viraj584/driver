/// Results supported by approved identity, liveness, and payout providers.
/// No provider is configured in this application yet.
enum ProviderOperationStatus {
  pending,
  verified,
  rejected,
  failed,
  unavailable,
}

class ProviderOperationResult {
  const ProviderOperationResult(this.status, {this.reference});

  final ProviderOperationStatus status;
  final String? reference;
}

abstract interface class IdentityVerificationGateway {
  Future<ProviderOperationResult> beginVerification();
}

abstract interface class FaceLivenessGateway {
  Future<ProviderOperationResult> verify({
    required String operationId,
    required String phase,
  });
}

abstract interface class DriverPayoutGateway {
  Future<ProviderOperationResult> getPayoutStatus(String payoutId);
  Future<ProviderOperationResult> retryPayout(String payoutId);
}

class UnavailableIdentityVerificationGateway
    implements IdentityVerificationGateway {
  @override
  Future<ProviderOperationResult> beginVerification() async =>
      const ProviderOperationResult(ProviderOperationStatus.unavailable);
}

class UnavailableFaceLivenessGateway implements FaceLivenessGateway {
  @override
  Future<ProviderOperationResult> verify({
    required String operationId,
    required String phase,
  }) async =>
      const ProviderOperationResult(ProviderOperationStatus.unavailable);
}

class UnavailableDriverPayoutGateway implements DriverPayoutGateway {
  @override
  Future<ProviderOperationResult> getPayoutStatus(String payoutId) async =>
      const ProviderOperationResult(ProviderOperationStatus.unavailable);

  @override
  Future<ProviderOperationResult> retryPayout(String payoutId) async =>
      const ProviderOperationResult(ProviderOperationStatus.unavailable);
}
