/// Deterministic demonstration scoring. Scores are policy signals, not
/// probabilities of fraud. Severe account actions require an administrator.
enum RiskEventType {
  normal,
  deviceChange,
  gpsJump,
  unusualSpeed,
  possibleHandoff,
}

enum RiderRiskStatus { active, verificationPending, restricted }

class RiskEvaluation {
  const RiskEvaluation({
    required this.score,
    required this.reasons,
    required this.status,
    required this.reviewRequired,
  });

  final double score;
  final List<String> reasons;
  final RiderRiskStatus status;
  final bool reviewRequired;
}

class RiskEngine {
  const RiskEngine();

  RiskEvaluation evaluate({
    required RiskEventType event,
    required RiderRiskStatus currentStatus,
    bool poorLocationAccuracy = false,
    bool verified = false,
  }) {
    var score = 0.0;
    final reasons = <String>[];
    switch (event) {
      case RiskEventType.normal:
        break;
      case RiskEventType.deviceChange:
        score += 0.30;
        reasons.add('DEVICE_CHANGE');
      case RiskEventType.gpsJump:
        if (poorLocationAccuracy) {
          score += 0.05;
          reasons.add('GPS_UNCERTAIN');
        } else {
          score += 0.35;
          reasons.add('GPS_DISCONTINUITY');
        }
      case RiskEventType.unusualSpeed:
        score += 0.35;
        reasons.add('IMPLAUSIBLE_SPEED_DELTA');
      case RiskEventType.possibleHandoff:
        score += 0.30 + 0.35;
        reasons.addAll(['DEVICE_CHANGE', 'INCONSISTENT_SESSION']);
    }
    if (verified) {
      score = (score - 0.25).clamp(0.0, 1.0);
      reasons.add('VERIFICATION_PASSED');
    }
    score = score.clamp(0.0, 1.0);
    final next = currentStatus == RiderRiskStatus.restricted
        ? currentStatus
        : score >= 0.60
        ? RiderRiskStatus.verificationPending
        : currentStatus == RiderRiskStatus.verificationPending && !verified
        ? RiderRiskStatus.verificationPending
        : RiderRiskStatus.active;
    if (next == RiderRiskStatus.verificationPending) {
      reasons.add('VERIFICATION_REQUIRED');
    }
    return RiskEvaluation(
      score: double.parse(score.toStringAsFixed(2)),
      reasons: List.unmodifiable(reasons),
      status: next,
      reviewRequired:
          score >= 0.85 || currentStatus == RiderRiskStatus.restricted,
    );
  }
}
