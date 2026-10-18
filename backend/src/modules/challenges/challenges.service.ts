import { getDatabase } from '../../db/database.js';
import { AppError } from '../../middleware/errorHandler.js';
import { AuditService } from '../audit/audit.service.js';

export class ChallengesService {
  static getPendingChallenges(userId: string): any[] {
    const db = getDatabase();
    const rows = db.prepare(`
      SELECT id, request_id as requestId, challenge_type as challengeType,
             status, review_required as reviewRequired,
             expires_at as expiresAt, created_at as createdAt
      FROM verification_challenges
      WHERE rider_id = ? AND status = 'PENDING' AND expires_at > ?
      ORDER BY created_at DESC
    `).all(userId, Date.now());

    return rows.map((r: any) => ({
      ...r,
      reviewRequired: Boolean(r.reviewRequired),
    }));
  }

  static resolveChallenge(
    userId: string,
    identifier: string,
    passed: boolean
  ): { recorded: boolean; duplicate?: boolean; expired?: boolean; resultingStatus: string } {
    const db = getDatabase();

    // Match by challenge id or by request_id
    const challenge = db.prepare(`
      SELECT * FROM verification_challenges
      WHERE (id = ? OR request_id = ?) AND rider_id = ?
    `).get(identifier, identifier, userId) as any;

    if (!challenge) {
      throw new AppError('Challenge not found', 404, 'NOT_FOUND');
    }

    const expectedResult = passed ? 'DEMO_PASSED' : 'DEMO_FAILED';
    if (challenge.status !== 'PENDING') {
      if (challenge.status === expectedResult) {
        return { recorded: true, duplicate: true, resultingStatus: 'LIVENESS_PENDING' };
      }
      if (challenge.status === 'EXPIRED') {
        return { recorded: false, expired: true, duplicate: true, resultingStatus: 'LIVENESS_PENDING' };
      }
      throw new AppError('Challenge already has a different recorded result', 409, 'ALREADY_EXISTS');
    }

    const now = Date.now();
    const isExpired = challenge.expires_at <= now;

    if (isExpired) {
      const updateChallenge = db.prepare(`
        UPDATE verification_challenges
        SET status = 'EXPIRED', result_source = 'SERVER_TIMEOUT', review_required = 1, completed_at = ?
        WHERE id = ?
      `);

      const updateRider = db.prepare(`
        UPDATE rider_profiles SET review_required = 1, updated_at = ? WHERE user_id = ?
      `);

      const tx = db.transaction(() => {
        updateChallenge.run(now, challenge.id);
        updateRider.run(now, userId);
      });
      tx();

      AuditService.record({
        actorUid: userId,
        actorRole: 'system',
        riderId: userId,
        action: 'DEMO_CHALLENGE_EXPIRED',
        reason: 'CHALLENGE_TIMEOUT',
        previousStatus: 'LIVENESS_PENDING',
        newStatus: 'LIVENESS_PENDING',
        requestId: challenge.request_id,
      });

      return { recorded: false, expired: true, duplicate: false, resultingStatus: 'LIVENESS_PENDING' };
    }

    const updateChallenge = db.prepare(`
      UPDATE verification_challenges
      SET status = ?, result_source = 'SIMULATED', review_required = 1, completed_at = ?
      WHERE id = ?
    `);

    const updateRider = db.prepare(`
      UPDATE rider_profiles SET review_required = 1, updated_at = ? WHERE user_id = ?
    `);

    const tx = db.transaction(() => {
      updateChallenge.run(expectedResult, now, challenge.id);
      updateRider.run(now, userId);
    });
    tx();

    AuditService.record({
      actorUid: userId,
      actorRole: 'rider',
      riderId: userId,
      action: 'DEMO_CHALLENGE_RESULT_RECORDED',
      reason: expectedResult,
      previousStatus: 'LIVENESS_PENDING',
      newStatus: 'LIVENESS_PENDING',
      requestId: challenge.request_id,
    });

    // Client simulated evidence cannot clear real restricted/pending account status
    return { recorded: true, duplicate: false, resultingStatus: 'LIVENESS_PENDING' };
  }
}
