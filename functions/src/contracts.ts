export interface IdentityVerificationRequest {
  driverUid: string;
  provider: 'digilocker';
  providerReference: string;
}

export interface IdentityVerificationResult {
  status: 'pending' | 'verified' | 'rejected' | 'unavailable';
  verificationEventId: string | null;
}

export interface IdentityVerificationProvider {
  verifyRegistration(request: IdentityVerificationRequest): Promise<IdentityVerificationResult>;
}

export interface FaceVerificationRequest {
  driverUid: string;
  rideId: string;
  phase: 'before_start' | 'after_completion';
  challengeId: string;
}

export interface FaceVerificationResult {
  status: 'pending' | 'verified' | 'rejected' | 'unavailable';
  verificationEventId: string | null;
}

export interface FaceVerificationProvider {
  verifyLivenessAndMatch(request: FaceVerificationRequest): Promise<FaceVerificationResult>;
}

export interface RideTransitionRequest {
  driverUid: string;
  rideId: string;
  from: 'assigned' | 'in_progress' | 'completed' | 'cancelled';
  to: 'assigned' | 'in_progress' | 'completed' | 'cancelled';
  verificationEventIds: string[];
}

export interface RideTransitionAuthorizer {
  authorize(request: RideTransitionRequest): Promise<{ authorized: boolean; reasonCode: string }>;
}

export interface VerificationAuditEvent {
  eventId: string;
  driverUid: string;
  actorUid: string | null;
  eventType: string;
  status: 'pending' | 'verified' | 'rejected' | 'unavailable';
  providerReference?: string;
  createdAt: unknown;
}

export interface RiskAuditRecord {
  eventId: string;
  driverUid: string;
  score: number;
  reasonCodes: string[];
  recommendation: string;
  humanReviewRequired: boolean;
  createdAt: unknown;
}
