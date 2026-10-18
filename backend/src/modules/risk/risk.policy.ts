export type DemoRiskEvent =
  | 'NORMAL_TELEMETRY'
  | 'DEVICE_CHANGE'
  | 'GPS_JUMP'
  | 'GPS_JUMP_POOR_ACCURACY'
  | 'UNUSUAL_SPEED'
  | 'POSSIBLE_HANDOFF';

export type ServerRiderStatus = 'ACTIVE' | 'LIVENESS_PENDING' | 'RESTRICTED';

export interface ServerRiskEvaluation {
  score: number;
  reasons: string[];
  status: ServerRiderStatus;
  verificationRequired: boolean;
  reviewRequired: boolean;
}

export function evaluateDemoRisk(
  event: DemoRiskEvent,
  currentStatus: ServerRiderStatus
): ServerRiskEvaluation {
  const scoreByEvent: Record<DemoRiskEvent, number> = {
    NORMAL_TELEMETRY: 0,
    DEVICE_CHANGE: 0.3,
    GPS_JUMP: 0.35,
    GPS_JUMP_POOR_ACCURACY: 0.05,
    UNUSUAL_SPEED: 0.35,
    POSSIBLE_HANDOFF: 0.65,
  };

  const reasonsByEvent: Record<DemoRiskEvent, string[]> = {
    NORMAL_TELEMETRY: [],
    DEVICE_CHANGE: ['DEVICE_CHANGE'],
    GPS_JUMP: ['GPS_DISCONTINUITY'],
    GPS_JUMP_POOR_ACCURACY: ['GPS_UNCERTAIN'],
    UNUSUAL_SPEED: ['IMPLAUSIBLE_SPEED_DELTA'],
    POSSIBLE_HANDOFF: ['DEVICE_CHANGE', 'INCONSISTENT_SESSION'],
  };

  const score = scoreByEvent[event] ?? 0;
  const verificationRequired = score >= 0.6 && currentStatus !== 'RESTRICTED';
  const status = currentStatus === 'RESTRICTED'
    ? currentStatus
    : verificationRequired
    ? 'LIVENESS_PENDING'
    : currentStatus;

  const reasons = [...(reasonsByEvent[event] || [])];
  if (verificationRequired) reasons.push('VERIFICATION_REQUIRED');
  if (score >= 0.85) reasons.push('MANUAL_REVIEW_REQUIRED');

  return {
    score,
    reasons,
    status,
    verificationRequired,
    reviewRequired: score >= 0.85 || currentStatus === 'RESTRICTED',
  };
}

export const validDemoRiskEvents: DemoRiskEvent[] = [
  'NORMAL_TELEMETRY',
  'DEVICE_CHANGE',
  'GPS_JUMP',
  'GPS_JUMP_POOR_ACCURACY',
  'UNUSUAL_SPEED',
  'POSSIBLE_HANDOFF',
];
