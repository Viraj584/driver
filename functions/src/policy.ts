export type RegistrationStatus =
  | 'registration_pending'
  | 'identity_pending'
  | 'approved'
  | 'rejected'
  | 'suspended';

export type DeviceStatus = 'pending_review' | 'active' | 'revoked' | 'rejected';

export interface DriverAccessRecord {
  role: string;
  accountStatus: string;
  registrationStatus: RegistrationStatus;
  identityVerificationStatus: string;
  deviceEnrollmentStatus: string;
}

export function mayAdminister(claims: Record<string, unknown>): boolean {
  return claims.admin === true;
}

export function isAuthenticated(uid: unknown): uid is string {
  return typeof uid === 'string' && uid.length > 0;
}

export function mayStartRide(
  driver: DriverAccessRecord,
  activeDevice: boolean,
  faceVerificationEventId: string | null,
): boolean {
  return (
    driver.role === 'driver' &&
    driver.accountStatus === 'active' &&
    driver.registrationStatus === 'approved' &&
    driver.identityVerificationStatus === 'verified' &&
    driver.deviceEnrollmentStatus === 'enrolled' &&
    activeDevice &&
    faceVerificationEventId !== null
  );
}

export function assertValidPlatform(platform: unknown): asserts platform is 'android' | 'ios' {
  if (platform !== 'android' && platform !== 'ios') {
    throw new TypeError('platform must be android or ios');
  }
}
