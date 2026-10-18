import crypto from 'crypto';
import { getDatabase } from '../../db/database.js';
import { AppError } from '../../middleware/errorHandler.js';
import { AuditService } from '../audit/audit.service.js';

export class RidersService {
  static ensureProfile(userId: string): { created: boolean } {
    const db = getDatabase();
    const existing = db.prepare('SELECT user_id FROM rider_profiles WHERE user_id = ?').get(userId);
    if (existing) {
      return { created: false };
    }

    const now = Date.now();
    db.prepare(`
      INSERT INTO rider_profiles (
        user_id, registration_status, identity_verification_status,
        device_enrollment_status, risk_status, risk_score, risk_reasons,
        review_required, created_at, updated_at
      ) VALUES (?, 'registration_pending', 'identity_pending', 'none', 'ACTIVE', 0.0, '[]', 0, ?, ?)
    `).run(userId, now, now);

    return { created: true };
  }

  static getProfile(userId: string): any {
    const db = getDatabase();
    this.ensureProfile(userId);

    const row = db.prepare(`
      SELECT 
        u.id as userId, u.email, u.phone, u.role, u.account_status as accountStatus,
        r.registration_status as registrationStatus,
        r.identity_verification_status as identityVerificationStatus,
        r.device_enrollment_status as deviceEnrollmentStatus,
        r.risk_status as riskStatus,
        r.risk_score as riskScore,
        r.risk_reasons as riskReasons,
        r.review_required as reviewRequired,
        r.created_at as createdAt,
        r.updated_at as updatedAt
      FROM users u
      LEFT JOIN rider_profiles r ON u.id = r.user_id
      WHERE u.id = ?
    `).get(userId) as any;

    if (!row) {
      throw new AppError('Rider profile not found', 404, 'NOT_FOUND');
    }

    return {
      userId: row.userId,
      email: row.email,
      phone: row.phone,
      role: row.role,
      accountStatus: row.accountStatus,
      registrationStatus: row.registrationStatus || 'registration_pending',
      identityVerificationStatus: row.identityVerificationStatus || 'identity_pending',
      deviceEnrollmentStatus: row.deviceEnrollmentStatus || 'none',
      riskStatus: row.riskStatus || 'ACTIVE',
      riskScore: row.riskScore || 0.0,
      riskReasons: typeof row.riskReasons === 'string' ? JSON.parse(row.riskReasons) : (row.riskReasons || []),
      reviewRequired: Boolean(row.reviewRequired),
    };
  }

  static requestDeviceEnrollment(userId: string, platform: 'android' | 'ios'): { deviceEnrollmentId: string; status: string } {
    const db = getDatabase();
    this.ensureProfile(userId);

    const deviceId = `dev_${crypto.randomUUID()}`;
    const now = Date.now();

    const insertDevice = db.prepare(`
      INSERT INTO devices (id, rider_id, platform, status, created_at, updated_at)
      VALUES (?, ?, ?, 'pending_review', ?, ?)
    `);

    const updateRider = db.prepare(`
      UPDATE rider_profiles
      SET device_enrollment_status = 'pending_review', updated_at = ?
      WHERE user_id = ?
    `);

    const tx = db.transaction(() => {
      insertDevice.run(deviceId, userId, platform, now, now);
      updateRider.run(now, userId);
    });
    tx();

    AuditService.record({
      actorUid: userId,
      actorRole: 'rider',
      riderId: userId,
      action: 'DEVICE_ENROLLMENT_REQUESTED',
      reason: `Device enrollment for platform: ${platform}`,
    });

    return {
      deviceEnrollmentId: deviceId,
      status: 'pending_review',
    };
  }

  static revokeDevice(userId: string, deviceId: string): { revoked: boolean } {
    const db = getDatabase();
    const device = db.prepare('SELECT id, status FROM devices WHERE id = ? AND rider_id = ?').get(deviceId, userId) as any;

    if (!device) {
      throw new AppError('Device enrollment not found', 404, 'NOT_FOUND');
    }

    const now = Date.now();
    const updateDevice = db.prepare('UPDATE devices SET status = \'revoked\', updated_at = ? WHERE id = ?');

    const tx = db.transaction(() => {
      updateDevice.run(now, deviceId);
      const remainingActive = db.prepare(`
        SELECT COUNT(*) as count FROM devices WHERE rider_id = ? AND status = 'active'
      `).get(userId) as { count: number };

      const newEnrollmentStatus = remainingActive.count > 0 ? 'enrolled' : 'none';
      db.prepare(`
        UPDATE rider_profiles SET device_enrollment_status = ?, updated_at = ? WHERE user_id = ?
      `).run(newEnrollmentStatus, now, userId);
    });
    tx();

    AuditService.record({
      actorUid: userId,
      actorRole: 'rider',
      riderId: userId,
      action: 'DEVICE_REVOKED',
      reason: `Device ${deviceId} revoked by rider`,
    });

    return { revoked: true };
  }
}
