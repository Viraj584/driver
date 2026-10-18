import crypto from 'crypto';
import { getDatabase } from '../../db/database.js';
import { AppError } from '../../middleware/errorHandler.js';
import { AuditService } from '../audit/audit.service.js';

export class AdminService {
  static listRiders(): any[] {
    const db = getDatabase();
    const rows = db.prepare(`
      SELECT 
        u.id, u.email, u.phone, u.role, u.account_status as accountStatus,
        r.registration_status as registrationStatus,
        r.identity_verification_status as identityVerificationStatus,
        r.device_enrollment_status as deviceEnrollmentStatus,
        r.risk_status as riskStatus,
        r.risk_score as riskScore,
        r.risk_reasons as riskReasons,
        r.review_required as reviewRequired,
        u.created_at as createdAt,
        u.updated_at as updatedAt
      FROM users u
      LEFT JOIN rider_profiles r ON u.id = r.user_id
      WHERE u.role = 'driver'
      ORDER BY u.created_at DESC
    `).all() as any[];

    return rows.map(r => ({
      ...r,
      riskReasons: typeof r.riskReasons === 'string' ? JSON.parse(r.riskReasons) : (r.riskReasons || []),
      reviewRequired: Boolean(r.reviewRequired),
    }));
  }

  static getFleetRiskEvents(limit = 50): any[] {
    const db = getDatabase();
    const rows = db.prepare(`
      SELECT 
        e.id, e.request_id as requestId, e.rider_id as riderId,
        e.event_type as eventType, e.source, e.risk_score as riskScore,
        e.risk_reasons as riskReasons, e.resulting_status as resultingStatus,
        e.verification_required as verificationRequired,
        e.review_required as reviewRequired,
        e.received_at as receivedAt,
        COALESCE(r.risk_status, 'ACTIVE') as currentStatus
      FROM risk_events e
      LEFT JOIN rider_profiles r ON e.rider_id = r.user_id
      ORDER BY e.received_at DESC
      LIMIT ?
    `).all(limit) as any[];

    return rows.map(r => ({
      ...r,
      riskReasons: typeof r.riskReasons === 'string' ? JSON.parse(r.riskReasons) : r.riskReasons,
      verificationRequired: Boolean(r.verificationRequired),
      reviewRequired: Boolean(r.reviewRequired),
    }));
  }

  static getFleetAuditLogs(limit = 50): any[] {
    return AuditService.getHistory(limit);
  }

  static reviewRider(
    adminUid: string,
    riderId: string,
    action: 'APPROVE_SESSION' | 'RESTRICT_ACCOUNT',
    reason: string,
    requestId?: string
  ): { updated: boolean; status: string; duplicate?: boolean } {
    const db = getDatabase();
    const effectiveRequestId = requestId || `rev_${crypto.randomUUID()}`;

    // Check duplicate review with same request id
    const existingAudit = db.prepare(`
      SELECT * FROM audit_logs WHERE actor_uid = ? AND request_id = ?
    `).get(adminUid, effectiveRequestId) as any;

    if (existingAudit) {
      return { updated: true, duplicate: true, status: existingAudit.new_status };
    }

    const rider = db.prepare('SELECT user_id, risk_status, risk_score FROM rider_profiles WHERE user_id = ?').get(riderId) as any;
    if (!rider) {
      throw new AppError('Rider not found', 404, 'NOT_FOUND');
    }

    const previousStatus = rider.risk_status || 'ACTIVE';

    if (action === 'APPROVE_SESSION' && previousStatus !== 'LIVENESS_PENDING') {
      throw new AppError('Only pending sessions can be approved', 412, 'FAILED_PRECONDITION');
    }

    const newStatus = action === 'RESTRICT_ACCOUNT' ? 'RESTRICTED' : 'ACTIVE';
    const now = Date.now();

    const updateRider = db.prepare(`
      UPDATE rider_profiles
      SET risk_status = ?, review_required = 0, updated_at = ?
      WHERE user_id = ?
    `);

    const updateUserAccount = db.prepare(`
      UPDATE users SET account_status = ?, updated_at = ? WHERE id = ?
    `);

    const tx = db.transaction(() => {
      updateRider.run(newStatus, now, riderId);
      if (action === 'RESTRICT_ACCOUNT') {
        updateUserAccount.run('restricted', now, riderId);
      } else {
        updateUserAccount.run('active', now, riderId);
      }
    });

    tx();

    AuditService.record({
      actorUid: adminUid,
      actorRole: 'admin',
      riderId,
      action,
      reason: reason.trim(),
      previousStatus,
      newStatus,
      riskScore: rider.risk_score,
      requestId: effectiveRequestId,
    });

    return { updated: true, duplicate: false, status: newStatus };
  }

  static reviewDevice(
    adminUid: string,
    driverUid: string,
    deviceId: string,
    approve: boolean
  ): { status: string } {
    const db = getDatabase();
    const device = db.prepare('SELECT id, status FROM devices WHERE id = ? AND rider_id = ?').get(deviceId, driverUid) as any;

    if (!device) {
      throw new AppError('Device enrollment not found', 404, 'NOT_FOUND');
    }

    if (device.status !== 'pending_review') {
      throw new AppError('Only pending devices can be reviewed', 412, 'FAILED_PRECONDITION');
    }

    const now = Date.now();
    const newStatus = approve ? 'active' : 'rejected';

    const tx = db.transaction(() => {
      if (approve) {
        db.prepare("UPDATE devices SET status = 'revoked', updated_at = ? WHERE rider_id = ? AND status = 'active'").run(now, driverUid);
      }
      db.prepare('UPDATE devices SET status = ?, updated_at = ? WHERE id = ?').run(newStatus, now, deviceId);
      db.prepare('UPDATE rider_profiles SET device_enrollment_status = ?, updated_at = ? WHERE user_id = ?').run(approve ? 'enrolled' : 'none', now, driverUid);
    });

    tx();

    AuditService.record({
      actorUid: adminUid,
      actorRole: 'admin',
      riderId: driverUid,
      action: approve ? 'DEVICE_ENROLLMENT_APPROVED' : 'DEVICE_ENROLLMENT_REJECTED',
      reason: `Device ${deviceId} review outcome: ${newStatus}`,
    });

    return { status: newStatus };
  }

  static updateRegistration(
    adminUid: string,
    riderId: string,
    registrationStatus: string
  ): { updated: boolean } {
    const db = getDatabase();
    const profile = db.prepare('SELECT user_id, registration_status FROM rider_profiles WHERE user_id = ?').get(riderId) as any;
    if (!profile) {
      throw new AppError('Rider not found', 404, 'NOT_FOUND');
    }

    const now = Date.now();
    db.prepare('UPDATE rider_profiles SET registration_status = ?, updated_at = ? WHERE user_id = ?').run(registrationStatus, now, riderId);

    AuditService.record({
      actorUid: adminUid,
      actorRole: 'admin',
      riderId,
      action: 'ADMIN_REGISTRATION_STATUS_CHANGED',
      reason: `Status updated from ${profile.registration_status} to ${registrationStatus}`,
    });

    return { updated: true };
  }
}
