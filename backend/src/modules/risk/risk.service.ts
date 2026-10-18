import crypto from 'crypto';
import { getDatabase } from '../../db/database.js';
import { evaluateDemoRisk, DemoRiskEvent, ServerRiderStatus } from './risk.policy.js';
import { AppError } from '../../middleware/errorHandler.js';
import { AuditService } from '../audit/audit.service.js';
import { APP_CONSTANTS } from '../../config/constants.js';

export class RiskService {
  static submitRiskEvent(
    userId: string,
    data: { requestId: string; eventType: DemoRiskEvent; source: 'SIMULATOR' | 'APP' }
  ): any {
    const db = getDatabase();

    // Idempotency check
    const existing = db.prepare(`
      SELECT * FROM risk_events WHERE rider_id = ? AND request_id = ?
    `).get(userId, data.requestId) as any;

    if (existing) {
      if (existing.event_type !== data.eventType) {
        throw new AppError('Request ID was already used for a different event', 409, 'ALREADY_EXISTS');
      }

      return {
        requestId: existing.request_id,
        score: existing.risk_score,
        reasons: JSON.parse(existing.risk_reasons),
        status: existing.resulting_status,
        verificationRequired: Boolean(existing.verification_required),
        reviewRequired: Boolean(existing.review_required),
        duplicate: true,
      };
    }

    // Get current rider status
    const rider = db.prepare(`
      SELECT risk_status FROM rider_profiles WHERE user_id = ?
    `).get(userId) as { risk_status: string } | undefined;

    const currentStatus: ServerRiderStatus = (rider?.risk_status as ServerRiderStatus) || 'ACTIVE';
    const evaluation = evaluateDemoRisk(data.eventType, currentStatus);

    const now = Date.now();
    const eventId = `rsk_${crypto.randomUUID()}`;
    const reasonsJson = JSON.stringify(evaluation.reasons);

    const insertEvent = db.prepare(`
      INSERT INTO risk_events (
        id, request_id, rider_id, event_type, source,
        risk_score, risk_reasons, resulting_status,
        verification_required, review_required, evaluation_version, received_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'demo-v1', ?)
    `);

    const updateRider = db.prepare(`
      INSERT INTO rider_profiles (user_id, risk_status, risk_score, risk_reasons, review_required, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(user_id) DO UPDATE SET
        risk_status = excluded.risk_status,
        risk_score = excluded.risk_score,
        risk_reasons = excluded.risk_reasons,
        review_required = excluded.review_required,
        updated_at = excluded.updated_at
    `);

    const insertChallenge = db.prepare(`
      INSERT OR IGNORE INTO verification_challenges (
        id, request_id, rider_id, challenge_type, status,
        result_source, review_required, expires_at, created_at
      ) VALUES (?, ?, ?, 'DEMO_STEP_UP', 'PENDING', NULL, 1, ?, ?)
    `);

    const tx = db.transaction(() => {
      insertEvent.run(
        eventId,
        data.requestId,
        userId,
        data.eventType,
        data.source,
        evaluation.score,
        reasonsJson,
        evaluation.status,
        evaluation.verificationRequired ? 1 : 0,
        evaluation.reviewRequired ? 1 : 0,
        now
      );

      updateRider.run(
        userId,
        evaluation.status,
        evaluation.score,
        reasonsJson,
        evaluation.reviewRequired ? 1 : 0,
        now,
        now
      );

      if (evaluation.verificationRequired) {
        const challengeId = `ch_${crypto.randomUUID()}`;
        const expiresAt = now + APP_CONSTANTS.CHALLENGE_TIMEOUT_MINUTES * 60 * 1000;
        insertChallenge.run(challengeId, data.requestId, userId, expiresAt, now);
      }
    });

    tx();

    AuditService.record({
      actorUid: userId,
      actorRole: 'rider',
      riderId: userId,
      sessionId: eventId,
      action: 'RISK_EVALUATED',
      reason: evaluation.reasons.join(',') || 'NORMAL_TELEMETRY',
      previousStatus: currentStatus,
      newStatus: evaluation.status,
      riskScore: evaluation.score,
      requestId: data.requestId,
    });

    return {
      requestId: data.requestId,
      score: evaluation.score,
      reasons: evaluation.reasons,
      status: evaluation.status,
      verificationRequired: evaluation.verificationRequired,
      reviewRequired: evaluation.reviewRequired,
      duplicate: false,
    };
  }

  static getHistory(userId: string, limit = 30): any {
    const db = getDatabase();
    const rider = db.prepare('SELECT risk_status FROM rider_profiles WHERE user_id = ?').get(userId) as any;
    const currentStatus = rider?.risk_status || 'ACTIVE';

    const rows = db.prepare(`
      SELECT 
        id, request_id as requestId, rider_id as riderId,
        event_type as eventType, source, risk_score as riskScore,
        risk_reasons as riskReasons, resulting_status as resultingStatus,
        verification_required as verificationRequired,
        review_required as reviewRequired,
        received_at as receivedAt
      FROM risk_events
      WHERE rider_id = ?
      ORDER BY received_at DESC
      LIMIT ?
    `).all(userId, limit) as any[];

    const events = rows.map(r => ({
      ...r,
      riskReasons: typeof r.riskReasons === 'string' ? JSON.parse(r.riskReasons) : r.riskReasons,
      verificationRequired: Boolean(r.verificationRequired),
      reviewRequired: Boolean(r.reviewRequired),
      currentStatus,
    }));

    return {
      currentStatus,
      events,
    };
  }

  static getState(userId: string): any {
    const db = getDatabase();
    const rider = db.prepare(`
      SELECT risk_status, risk_score, risk_reasons, review_required
      FROM rider_profiles
      WHERE user_id = ?
    `).get(userId) as any;

    const pendingChallenges = db.prepare(`
      SELECT id, request_id as requestId, status, expires_at as expiresAt
      FROM verification_challenges
      WHERE rider_id = ? AND status = 'PENDING' AND expires_at > ?
    `).all(userId, Date.now()) as any[];

    return {
      riskStatus: rider?.risk_status || 'ACTIVE',
      riskScore: rider?.risk_score || 0.0,
      riskReasons: rider?.risk_reasons ? JSON.parse(rider.risk_reasons) : [],
      reviewRequired: Boolean(rider?.review_required),
      pendingChallenges,
    };
  }
}
