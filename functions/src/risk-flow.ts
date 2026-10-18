import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import {
  evaluateDemoRisk,
  isDemoRiskEvent,
  type ServerRiderStatus,
} from './risk-policy.js';

function uidFrom(request: { auth?: { uid: string } | null }): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in is required.');
  return uid;
}

function requestData(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new HttpsError('invalid-argument', 'A JSON object is required.');
  }
  return value as Record<string, unknown>;
}

export const submitRiskEvent = onCall(async request => {
  const uid = uidFrom(request);
  const data = requestData(request.data);
  const requestId = data.requestId;
  const eventType = data.eventType;
  const source = data.source;
  const allowedKeys = ['requestId', 'eventType', 'source'];
  if (Object.keys(data).some(key => !allowedKeys.includes(key))) {
    throw new HttpsError('invalid-argument', 'Unexpected event fields.');
  }
  if (
    typeof requestId !== 'string' ||
    !/^[A-Za-z0-9_-]{8,96}$/.test(requestId) ||
    !isDemoRiskEvent(eventType) ||
    (source !== 'APP' && source !== 'SIMULATOR')
  ) {
    throw new HttpsError('invalid-argument', 'Risk event payload is invalid.');
  }

  const db = getFirestore();
  const eventRef = db.collection('sessions').doc(`${uid}_${requestId}`);
  const riderRef = db.collection('riders').doc(uid);
  const rateRef = db.collection('_rateLimits').doc(`${uid}_submitRiskEvent`);
  const auditRef = db.collection('audit_logs').doc(`${uid}_${requestId}`);
  const challengeRef = db.collection('verification_challenges').doc(`${uid}_${requestId}`);

  return db.runTransaction(async transaction => {
    const [existingEvent, riderSnapshot, rateSnapshot] = await Promise.all([
      transaction.get(eventRef),
      transaction.get(riderRef),
      transaction.get(rateRef),
    ]);
    if (existingEvent.exists) {
      const existing = existingEvent.data()!;
      if (existing.riderId !== uid || existing.eventType !== eventType) {
        throw new HttpsError('already-exists', 'Request ID was already used.');
      }
      return {
        requestId,
        score: existing.riskScore,
        reasons: existing.riskReasons,
        status: existing.resultingStatus,
        verificationRequired: existing.verificationRequired,
        reviewRequired: existing.reviewRequired,
        duplicate: true,
      };
    }

    const currentStatus = (riderSnapshot.get('status') ?? 'ACTIVE') as ServerRiderStatus;
    if (!['ACTIVE', 'LIVENESS_PENDING', 'RESTRICTED'].includes(currentStatus)) {
      throw new HttpsError('failed-precondition', 'Rider state is invalid.');
    }
    const now = Date.now();
    const windowStartedAt = Number(rateSnapshot.get('windowStartedAt') ?? now);
    const sameWindow = now - windowStartedAt < 60_000;
    const count = sameWindow ? Number(rateSnapshot.get('count') ?? 0) : 0;
    if (count >= 60) {
      throw new HttpsError('resource-exhausted', 'Too many risk events. Try again later.');
    }
    const result = evaluateDemoRisk(eventType, currentStatus);
    const serverTimestamp = FieldValue.serverTimestamp();
    const eventRecord = {
      riderId: uid,
      eventType,
      source,
      observedAt: null,
      receivedAt: serverTimestamp,
      riskScore: result.score,
      riskReasons: result.reasons,
      resultingStatus: result.status,
      verificationRequired: result.verificationRequired,
      reviewRequired: result.reviewRequired,
      evaluationVersion: 'demo-v1',
      requestId,
    };
    transaction.create(eventRef, eventRecord);
    transaction.set(rateRef, {
      windowStartedAt: sameWindow ? windowStartedAt : now,
      count: count + 1,
      expiresAt: Timestamp.fromMillis(now + 24 * 60 * 60 * 1000),
    });
    transaction.set(riderRef, {
      status: result.status,
      riskScore: result.score,
      riskReasons: result.reasons,
      reviewRequired: result.reviewRequired,
      lastSeenAt: serverTimestamp,
      updatedAt: serverTimestamp,
      createdAt: riderSnapshot.exists
        ? riderSnapshot.get('createdAt') ?? serverTimestamp
        : serverTimestamp,
    }, { merge: true });
    transaction.create(auditRef, {
      actorUid: uid,
      actorRole: 'rider',
      riderId: uid,
      sessionId: eventRef.id,
      action: 'RISK_EVALUATED',
      reason: result.reasons.join(',') || 'NORMAL_TELEMETRY',
      previousStatus: currentStatus,
      newStatus: result.status,
      riskScore: result.score,
      requestId,
      createdAt: serverTimestamp,
    });
    if (result.verificationRequired) {
      transaction.create(challengeRef, {
        riderId: uid,
        sessionId: eventRef.id,
        challengeType: 'DEMO_STEP_UP',
        status: 'PENDING',
        resultSource: null,
        reviewRequired: true,
        createdAt: serverTimestamp,
        expiresAt: Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
        completedAt: null,
      });
    }
    return {
        requestId,
      score: result.score,
      reasons: result.reasons,
      status: result.status,
      verificationRequired: result.verificationRequired,
      reviewRequired: result.reviewRequired,
      duplicate: false,
    };
  });
});

export const getRiskEventHistory = onCall(async request => {
  const uid = uidFrom(request);
  const db = getFirestore();
  const snapshot = await db.collection('sessions')
    .where('riderId', '==', uid)
    .orderBy('receivedAt', 'desc')
    .limit(30)
    .get();
  const rider = await db.collection('riders').doc(uid).get();
  return {
    currentStatus: rider.get('status') ?? 'ACTIVE',
    events: snapshot.docs.map(document => {
      const data = document.data();
      return {
        id: document.id,
        requestId: data.requestId,
        eventType: data.eventType,
        source: data.source,
        riskScore: data.riskScore,
        riskReasons: data.riskReasons,
        resultingStatus: data.resultingStatus,
        currentStatus: rider.get('status') ?? 'ACTIVE',
        verificationRequired: data.verificationRequired,
        reviewRequired: data.reviewRequired,
        receivedAt: data.receivedAt?.toMillis?.() ?? null,
      };
    }),
  };
});

export const getFleetRiskEventHistory = onCall(async request => {
  uidFrom(request);
  if (request.auth?.token.admin !== true) {
    throw new HttpsError('permission-denied', 'Administrator access is required.');
  }
  const db = getFirestore();
  const snapshot = await db.collection('sessions')
    .orderBy('receivedAt', 'desc')
    .limit(50)
    .get();
  const riderIds = [...new Set(snapshot.docs.map(document => String(document.get('riderId'))))];
  const riders = await Promise.all(riderIds.map(id => db.collection('riders').doc(id).get()));
  const statuses = new Map(riders.map(rider => [rider.id, rider.get('status') ?? 'ACTIVE']));
  return {
    events: snapshot.docs.map(document => {
      const data = document.data();
      return {
        id: document.id,
        requestId: data.requestId,
        riderId: data.riderId,
        eventType: data.eventType,
        source: data.source,
        riskScore: data.riskScore,
        riskReasons: data.riskReasons,
        resultingStatus: data.resultingStatus,
        currentStatus: statuses.get(String(data.riderId)) ?? 'ACTIVE',
        verificationRequired: data.verificationRequired,
        reviewRequired: data.reviewRequired,
        receivedAt: data.receivedAt?.toMillis?.() ?? null,
      };
    }),
  };
});

export const getFleetAuditHistory = onCall(async request => {
  uidFrom(request);
  if (request.auth?.token.admin !== true) {
    throw new HttpsError('permission-denied', 'Administrator access is required.');
  }
  const snapshot = await getFirestore().collection('audit_logs')
    .orderBy('createdAt', 'desc')
    .limit(50)
    .get();
  return {
    events: snapshot.docs.map(document => {
      const data = document.data();
      return {
        id: document.id,
        actorUid: data.actorUid,
        actorRole: data.actorRole,
        riderId: data.riderId,
        sessionId: data.sessionId,
        action: data.action,
        reason: data.reason,
        previousStatus: data.previousStatus,
        newStatus: data.newStatus,
        riskScore: data.riskScore,
        requestId: data.requestId,
        createdAt: data.createdAt?.toMillis?.() ?? null,
      };
    }),
  };
});

export const submitDemoChallengeResult = onCall(async request => {
  const uid = uidFrom(request);
  const data = requestData(request.data);
  if (
    Object.keys(data).some(key => !['requestId', 'passed'].includes(key)) ||
    typeof data.requestId !== 'string' ||
    !/^[A-Za-z0-9_-]{8,96}$/.test(data.requestId) ||
    typeof data.passed !== 'boolean'
  ) {
    throw new HttpsError('invalid-argument', 'Challenge result payload is invalid.');
  }
  const db = getFirestore();
  const challengeRef = db.collection('verification_challenges')
    .doc(`${uid}_${data.requestId}`);
  const auditRef = db.collection('audit_logs')
    .doc(`${uid}_${data.requestId}_challenge`);
  return db.runTransaction(async transaction => {
    const challenge = await transaction.get(challengeRef);
    if (!challenge.exists) {
      throw new HttpsError('not-found', 'Challenge was not found.');
    }
    if (challenge.get('riderId') !== uid) {
      throw new HttpsError('permission-denied', 'Challenge owner does not match.');
    }
    const result = data.passed ? 'DEMO_PASSED' : 'DEMO_FAILED';
    const existingResult = challenge.get('status');
    if (existingResult !== 'PENDING') {
      if (existingResult === result) return { recorded: true, duplicate: true };
      if (existingResult === 'EXPIRED') return { recorded: false, expired: true, duplicate: true };
      throw new HttpsError('already-exists', 'Challenge already has a result.');
    }
    const serverTimestamp = FieldValue.serverTimestamp();
    const riderRef = db.collection('riders').doc(uid);
    const rider = await transaction.get(riderRef);
    if (!rider.exists) throw new HttpsError('not-found', 'Rider was not found.');
    const expiresAt = challenge.get('expiresAt');
    if (expiresAt instanceof Timestamp && expiresAt.toMillis() <= Date.now()) {
      transaction.update(challengeRef, {
        status: 'EXPIRED',
        resultSource: 'SERVER_TIMEOUT',
        completedAt: serverTimestamp,
        reviewRequired: true,
      });
      transaction.update(riderRef, {
        reviewRequired: true,
        updatedAt: serverTimestamp,
      });
      transaction.create(auditRef, {
        actorUid: uid,
        actorRole: 'system',
        riderId: uid,
        sessionId: challenge.get('sessionId'),
        action: 'DEMO_CHALLENGE_EXPIRED',
        reason: 'CHALLENGE_TIMEOUT',
        previousStatus: 'LIVENESS_PENDING',
        newStatus: 'LIVENESS_PENDING',
        riskScore: null,
        requestId: data.requestId,
        createdAt: serverTimestamp,
      });
      return { recorded: false, expired: true, duplicate: false };
    }
    transaction.update(challengeRef, {
      status: result,
      resultSource: 'SIMULATED',
      completedAt: serverTimestamp,
      reviewRequired: true,
    });
    transaction.update(riderRef, {
      reviewRequired: true,
      updatedAt: serverTimestamp,
    });
    transaction.create(auditRef, {
      actorUid: uid,
      actorRole: 'rider',
      riderId: uid,
      sessionId: challenge.get('sessionId'),
      action: 'DEMO_CHALLENGE_RESULT_RECORDED',
      reason: result,
      previousStatus: 'LIVENESS_PENDING',
      newStatus: 'LIVENESS_PENDING',
      riskScore: null,
      requestId: data.requestId,
      createdAt: serverTimestamp,
    });
    // A client simulated interaction cannot clear or restrict a real account.
    return { recorded: true, duplicate: false, resultingStatus: 'LIVENESS_PENDING' };
  });
});

export const adminReviewRider = onCall(async request => {
  const adminUid = uidFrom(request);
  if (request.auth?.token.admin !== true) {
    throw new HttpsError('permission-denied', 'Administrator access is required.');
  }
  const data = requestData(request.data);
  const reviewReason = data.reason;
  const riderId = data.riderId;
  const requestId = data.requestId;
  const actionValue = data.action;
  const allowedKeys = ['riderId', 'requestId', 'action', 'reason'];
  if (
    Object.keys(data).some(key => !allowedKeys.includes(key)) ||
    typeof riderId !== 'string' || riderId.length < 1 || riderId.length > 128 ||
    typeof requestId !== 'string' ||
    !/^[A-Za-z0-9_-]{8,96}$/.test(requestId) ||
    !['APPROVE_SESSION', 'RESTRICT_ACCOUNT'].includes(String(actionValue)) ||
    typeof reviewReason !== 'string' || reviewReason.trim().length < 8 ||
    reviewReason.trim().length > 500
  ) {
    throw new HttpsError('invalid-argument', 'Review action or reason is invalid.');
  }
  const action = actionValue as 'APPROVE_SESSION' | 'RESTRICT_ACCOUNT';
  const db = getFirestore();
  const riderRef = db.collection('riders').doc(riderId as string);
  const auditRef = db.collection('audit_logs').doc(`admin_${adminUid}_${requestId}`);
  const rateRef = db.collection('_rateLimits').doc(`${adminUid}_adminReviewRider`);
  return db.runTransaction(async transaction => {
    const [rider, priorAudit, rate] = await Promise.all([
      transaction.get(riderRef), transaction.get(auditRef), transaction.get(rateRef),
    ]);
    if (priorAudit.exists) {
      if (priorAudit.get('action') !== action || priorAudit.get('riderId') !== riderId) {
        throw new HttpsError('already-exists', 'Request ID was already used.');
      }
      return { updated: true, duplicate: true, status: priorAudit.get('newStatus') };
    }
    if (!rider.exists) throw new HttpsError('not-found', 'Rider was not found.');
    const now = Date.now();
    const windowStartedAt = Number(rate.get('windowStartedAt') ?? now);
    const sameWindow = now - windowStartedAt < 60_000;
    const count = sameWindow ? Number(rate.get('count') ?? 0) : 0;
    if (count >= 10) {
      throw new HttpsError('resource-exhausted', 'Too many review actions. Try again later.');
    }
    const previousStatus = String(rider.get('status') ?? 'ACTIVE');
    if (action === 'APPROVE_SESSION' && previousStatus !== 'LIVENESS_PENDING') {
      throw new HttpsError('failed-precondition', 'Only pending sessions can be approved.');
    }
    const newStatus = action === 'RESTRICT_ACCOUNT' ? 'RESTRICTED' : 'ACTIVE';
    const serverTimestamp = FieldValue.serverTimestamp();
    transaction.update(riderRef, {
      status: newStatus,
      reviewRequired: false,
      reviewedAt: serverTimestamp,
      reviewedBy: adminUid,
      updatedAt: serverTimestamp,
    });
    transaction.set(rateRef, {
      windowStartedAt: sameWindow ? windowStartedAt : now,
      count: count + 1,
      expiresAt: Timestamp.fromMillis(now + 24 * 60 * 60 * 1000),
    });
    transaction.create(auditRef, {
      actorUid: adminUid,
      actorRole: 'admin',
      riderId,
      sessionId: null,
      action,
      reason: (reviewReason as string).trim(),
      previousStatus,
      newStatus,
      riskScore: rider.get('riskScore') ?? null,
      requestId,
      createdAt: serverTimestamp,
    });
    return { updated: true, duplicate: false, status: newStatus };
  });
});
