import { initializeApp } from 'firebase-admin/app';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall, type CallableRequest } from 'firebase-functions/v2/https';
import {
  assertValidPlatform,
  isAuthenticated,
  mayAdminister,
  mayStartRide,
  type RegistrationStatus,
} from './policy.js';
export {
  submitRiskEvent,
  getRiskEventHistory,
  getFleetRiskEventHistory,
  getFleetAuditHistory,
  submitDemoChallengeResult,
  adminReviewRider,
} from './risk-flow.js';

initializeApp();
const db = getFirestore();

function authenticatedUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!isAuthenticated(uid)) throw new HttpsError('unauthenticated', 'Sign in is required.');
  return uid;
}

function requireAdmin(request: CallableRequest): string {
  const uid = authenticatedUid(request);
  if (!mayAdminister(request.auth!.token)) {
    throw new HttpsError('permission-denied', 'Administrator access is required.');
  }
  return uid;
}

async function applyRateLimit(uid: string, operation: string): Promise<void> {
  const now = Date.now();
  const ref = db.collection('_rateLimits').doc(`${uid}_${operation}`);
  await db.runTransaction(async transaction => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.data();
    const windowStartedAt = Number(data?.windowStartedAt ?? now);
    const count = Number(data?.count ?? 0);
    if (now - windowStartedAt < 60_000 && count >= 10) {
      throw new HttpsError('resource-exhausted', 'Too many requests. Try again later.');
    }
    transaction.set(ref, {
      windowStartedAt: now - windowStartedAt >= 60_000 ? now : windowStartedAt,
      count: now - windowStartedAt >= 60_000 ? 1 : count + 1,
      expiresAt: Timestamp.fromMillis(now + 24 * 60 * 60 * 1000),
    });
  });
}

function objectData(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new HttpsError('invalid-argument', 'A JSON object is required.');
  }
  return value as Record<string, unknown>;
}

export const ensureDriverProfile = onCall(async request => {
  const uid = authenticatedUid(request);
  await applyRateLimit(uid, 'ensureDriverProfile');
  const ref = db.collection('drivers').doc(uid);
  let created = false;
  await db.runTransaction(async transaction => {
    const existing = await transaction.get(ref);
    if (existing.exists) return;
    created = true;
    transaction.create(ref, {
      uid,
      role: 'driver',
      accountStatus: 'active',
      registrationStatus: 'registration_pending',
      identityVerificationStatus: 'identity_pending',
      deviceEnrollmentStatus: 'none',
      verificationEventRefs: [],
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { created };
});

export const getDriverProfile = onCall(async request => {
  const uid = authenticatedUid(request);
  await applyRateLimit(uid, 'getDriverProfile');
  const snapshot = await db.collection('drivers').doc(uid).get();
  if (!snapshot.exists) throw new HttpsError('not-found', 'Driver profile is not initialized.');
  const data = snapshot.data()!;
  return {
    role: data.role,
    accountStatus: data.accountStatus,
    registrationStatus: data.registrationStatus,
    identityVerificationStatus: data.identityVerificationStatus,
    deviceEnrollmentStatus: data.deviceEnrollmentStatus,
  };
});

export const requestDeviceEnrollment = onCall(async request => {
  const uid = authenticatedUid(request);
  await applyRateLimit(uid, 'requestDeviceEnrollment');
  const data = objectData(request.data);
  if (Object.keys(data).some(key => key !== 'platform')) {
    throw new HttpsError('invalid-argument', 'Only platform may be submitted.');
  }
  try {
    assertValidPlatform(data.platform);
  } catch (error) {
    throw new HttpsError('invalid-argument', (error as Error).message);
  }
  const driverRef = db.collection('drivers').doc(uid);
  const driver = await driverRef.get();
  if (!driver.exists) throw new HttpsError('failed-precondition', 'Driver profile is required.');
  const deviceRef = driverRef.collection('devices').doc();
  await db.runTransaction(async transaction => {
    transaction.create(deviceRef, {
      platform: data.platform,
      status: 'pending_review',
      keyProofStatus: 'not_available',
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(driverRef, {
      deviceEnrollmentStatus: 'pending_review',
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { deviceEnrollmentId: deviceRef.id, status: 'pending_review' };
});

export const revokeOwnDevice = onCall(async request => {
  const uid = authenticatedUid(request);
  await applyRateLimit(uid, 'revokeOwnDevice');
  const data = objectData(request.data);
  if (typeof data.deviceEnrollmentId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(data.deviceEnrollmentId)) {
    throw new HttpsError('invalid-argument', 'A valid device enrollment ID is required.');
  }
  const driverRef = db.collection('drivers').doc(uid);
  const deviceRef = driverRef.collection('devices').doc(data.deviceEnrollmentId);
  await db.runTransaction(async transaction => {
    const device = await transaction.get(deviceRef);
    if (!device.exists) throw new HttpsError('not-found', 'Device enrollment was not found.');
    const remaining = await transaction.get(driverRef.collection('devices').where('status', '==', 'active'));
    transaction.update(deviceRef, { status: 'revoked', revokedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    transaction.update(driverRef, {
      deviceEnrollmentStatus: remaining.docs.some(item => item.id !== deviceRef.id) ? 'enrolled' : 'none',
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(db.collection('verificationEvents').doc(), {
      type: 'DEVICE_REVOKED',
      driverUid: uid,
      deviceEnrollmentId: deviceRef.id,
      actorUid: uid,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return { revoked: true };
});

export const reviewDeviceEnrollment = onCall(async request => {
  const adminUid = requireAdmin(request);
  await applyRateLimit(adminUid, 'reviewDeviceEnrollment');
  const data = objectData(request.data);
  if (
    typeof data.driverUid !== 'string' ||
    typeof data.deviceEnrollmentId !== 'string' ||
    typeof data.approve !== 'boolean' ||
    Object.keys(data).some(key => !['driverUid', 'deviceEnrollmentId', 'approve'].includes(key))
  ) {
    throw new HttpsError('invalid-argument', 'driverUid, deviceEnrollmentId and approve are required.');
  }
  const driverRef = db.collection('drivers').doc(data.driverUid);
  const selectedRef = driverRef.collection('devices').doc(data.deviceEnrollmentId);
  await db.runTransaction(async transaction => {
    const [driver, selected] = await Promise.all([transaction.get(driverRef), transaction.get(selectedRef)]);
    if (!driver.exists || !selected.exists) throw new HttpsError('not-found', 'Driver or device was not found.');
    if (selected.get('status') !== 'pending_review') throw new HttpsError('failed-precondition', 'Only pending devices can be reviewed.');
    if (data.approve) {
      const active = await transaction.get(driverRef.collection('devices').where('status', '==', 'active'));
      for (const oldDevice of active.docs) {
        transaction.update(oldDevice.ref, { status: 'revoked', revokedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
      }
    }
    transaction.update(selectedRef, {
      status: data.approve ? 'active' : 'rejected',
      reviewedBy: adminUid,
      reviewedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(driverRef, {
      deviceEnrollmentStatus: data.approve ? 'enrolled' : 'none',
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(db.collection('verificationEvents').doc(), {
      type: data.approve ? 'DEVICE_ENROLLMENT_APPROVED' : 'DEVICE_ENROLLMENT_REJECTED',
      driverUid: data.driverUid,
      deviceEnrollmentId: selectedRef.id,
      actorUid: adminUid,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return { status: data.approve ? 'active' : 'rejected' };
});

export const updateDriverRegistration = onCall(async request => {
  const adminUid = requireAdmin(request);
  await applyRateLimit(adminUid, 'updateDriverRegistration');
  const data = objectData(request.data);
  const allowed: RegistrationStatus[] = ['registration_pending', 'identity_pending', 'approved', 'rejected', 'suspended'];
  if (
    typeof data.driverUid !== 'string' ||
    typeof data.registrationStatus !== 'string' ||
    !allowed.includes(data.registrationStatus as RegistrationStatus) ||
    Object.keys(data).some(key => !['driverUid', 'registrationStatus'].includes(key))
  ) {
    throw new HttpsError('invalid-argument', 'Driver UID or registration status is invalid.');
  }
  const ref = db.collection('drivers').doc(data.driverUid);
  await db.runTransaction(async transaction => {
    const driver = await transaction.get(ref);
    if (!driver.exists) throw new HttpsError('not-found', 'Driver profile was not found.');
    transaction.update(ref, {
      registrationStatus: data.registrationStatus,
      updatedAt: FieldValue.serverTimestamp(),
      lastReviewedBy: adminUid,
    });
    transaction.create(db.collection('verificationEvents').doc(), {
      type: 'ADMIN_REGISTRATION_STATUS_CHANGED',
      driverUid: data.driverUid,
      registrationStatus: data.registrationStatus,
      actorUid: adminUid,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return { updated: true };
});

/** Contract endpoint stays closed until real identity and face providers exist. */
export const authorizeRideStart = onCall(async request => {
  const uid = authenticatedUid(request);
  await applyRateLimit(uid, 'authorizeRideStart');
  const driver = await db.collection('drivers').doc(uid).get();
  const activeDevices = driver.exists
    ? await db.collection('drivers').doc(uid).collection('devices').where('status', '==', 'active').limit(1).get()
    : null;
  const record = driver.data();
  const eligible = !!record && mayStartRide(
    {
      role: String(record.role ?? ''),
      accountStatus: String(record.accountStatus ?? ''),
      registrationStatus: record.registrationStatus as RegistrationStatus,
      identityVerificationStatus: String(record.identityVerificationStatus ?? ''),
      deviceEnrollmentStatus: String(record.deviceEnrollmentStatus ?? ''),
    },
    (activeDevices?.size ?? 0) > 0,
    null,
  );
  if (!eligible) throw new HttpsError('failed-precondition', 'Driver, identity, device, or face-verification requirements are not satisfied.');
  throw new HttpsError('failed-precondition', 'Ride authorization is disabled until a real face verification provider is configured.');
});
