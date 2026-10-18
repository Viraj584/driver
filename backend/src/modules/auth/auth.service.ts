import crypto from 'crypto';
import { getDatabase } from '../../db/database.js';
import { env } from '../../config/env.js';
import {
  hashPassword,
  verifyPassword,
  generateRandomToken,
  hashToken,
  generateAccessToken,
} from '../../utils/crypto.js';
import { AppError } from '../../middleware/errorHandler.js';
import { AuditService } from '../audit/audit.service.js';

interface UserRecord {
  id: string;
  email: string | null;
  phone: string | null;
  password_hash: string | null;
  role: 'driver' | 'admin';
  account_status: string;
  created_at: number;
  updated_at: number;
}

// In-memory store for development phone verification codes
const devPhoneVerificationStore = new Map<string, { phone: string; code: string; expiresAt: number }>();

export class AuthService {
  static async register(data: {
    email?: string;
    phone?: string;
    password?: string;
    role?: 'driver' | 'admin';
  }): Promise<{ token: string; refreshToken: string; user: any }> {
    const db = getDatabase();
    const normalizedEmail = data.email ? data.email.trim().toLowerCase() : null;
    const normalizedPhone = data.phone ? data.phone.trim() : null;
    const role = data.role || 'driver';

    // Check duplicate
    if (normalizedEmail) {
      const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(normalizedEmail);
      if (existing) {
        throw new AppError('An account with this email already exists', 409, 'EMAIL_EXISTS');
      }
    }
    if (normalizedPhone) {
      const existing = db.prepare('SELECT id FROM users WHERE phone = ?').get(normalizedPhone);
      if (existing) {
        throw new AppError('An account with this phone number already exists', 409, 'PHONE_EXISTS');
      }
    }

    const passwordHash = data.password ? await hashPassword(data.password) : null;
    const userId = `usr_${crypto.randomUUID()}`;
    const now = Date.now();

    const insertUser = db.prepare(`
      INSERT INTO users (id, email, phone, password_hash, role, account_status, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, 'active', ?, ?)
    `);

    const insertProfile = db.prepare(`
      INSERT INTO rider_profiles (
        user_id, registration_status, identity_verification_status,
        device_enrollment_status, risk_status, risk_score, risk_reasons,
        review_required, created_at, updated_at
      ) VALUES (?, 'registration_pending', 'identity_pending', 'none', 'ACTIVE', 0.0, '[]', 0, ?, ?)
    `);

    const tx = db.transaction(() => {
      insertUser.run(userId, normalizedEmail, normalizedPhone, passwordHash, role, now, now);
      if (role === 'driver') {
        insertProfile.run(userId, now, now);
      }
    });
    tx();

    AuditService.record({
      actorUid: userId,
      actorRole: role,
      riderId: role === 'driver' ? userId : null,
      action: 'USER_REGISTERED',
      reason: 'User account created',
      newStatus: 'active',
    });

    return this.createAuthSession({
      id: userId,
      email: normalizedEmail,
      phone: normalizedPhone,
      role,
      account_status: 'active',
      password_hash: passwordHash,
      created_at: now,
      updated_at: now,
    });
  }

  static async login(data: {
    identifier?: string;
    email?: string;
    phone?: string;
    password?: string;
  }): Promise<{ token: string; refreshToken: string; user: any }> {
    const db = getDatabase();
    const idf = (data.identifier || data.email || data.phone || '').trim();
    if (!idf) {
      throw new AppError('Email or phone is required', 400, 'IDENTIFIER_REQUIRED');
    }

    const user = db.prepare(`
      SELECT * FROM users WHERE email = ? OR phone = ?
    `).get(idf.toLowerCase(), idf) as UserRecord | undefined;

    if (!user) {
      throw new AppError('Invalid credentials', 401, 'INVALID_CREDENTIALS');
    }

    if (user.account_status === 'suspended') {
      throw new AppError('This account is suspended', 403, 'ACCOUNT_SUSPENDED');
    }

    if (!user.password_hash || !data.password) {
      throw new AppError('Password authentication is not configured for this account', 400, 'PASSWORD_NOT_SET');
    }

    const valid = await verifyPassword(data.password, user.password_hash);
    if (!valid) {
      throw new AppError('Invalid credentials', 401, 'INVALID_CREDENTIALS');
    }

    AuditService.record({
      actorUid: user.id,
      actorRole: user.role,
      riderId: user.role === 'driver' ? user.id : null,
      action: 'USER_LOGIN',
      reason: 'Password authentication succeeded',
    });

    return this.createAuthSession(user);
  }

  static async refresh(refreshToken: string): Promise<{ token: string; refreshToken: string }> {
    const db = getDatabase();
    const tokenHash = hashToken(refreshToken);
    const now = Date.now();

    const session = db.prepare(`
      SELECT s.id, s.user_id, s.expires_at, s.revoked_at,
             u.id as user_id, u.email, u.phone, u.role, u.account_status
      FROM refresh_sessions s
      JOIN users u ON s.user_id = u.id
      WHERE s.token_hash = ?
    `).get(tokenHash) as any;

    if (!session || session.revoked_at !== null || session.expires_at <= now) {
      throw new AppError('Invalid or expired refresh token', 401, 'INVALID_REFRESH_TOKEN');
    }

    if (session.account_status === 'suspended') {
      throw new AppError('Account is suspended', 403, 'ACCOUNT_SUSPENDED');
    }

    // Rotate refresh session: revoke current session
    db.prepare('UPDATE refresh_sessions SET revoked_at = ? WHERE id = ?').run(now, session.id);

    // Create new refresh session
    const newRawRefreshToken = generateRandomToken(40);
    const newTokenHash = hashToken(newRawRefreshToken);
    const newSessionId = `ses_${crypto.randomUUID()}`;
    const newExpiresAt = now + env.REFRESH_TOKEN_EXPIRES_DAYS * 24 * 60 * 60 * 1000;

    db.prepare(`
      INSERT INTO refresh_sessions (id, user_id, token_hash, expires_at, created_at)
      VALUES (?, ?, ?, ?, ?)
    `).run(newSessionId, session.user_id, newTokenHash, newExpiresAt, now);

    const accessToken = generateAccessToken({
      userId: session.user_id,
      email: session.email,
      phone: session.phone,
      role: session.role,
    });

    return {
      token: accessToken,
      refreshToken: newRawRefreshToken,
    };
  }

  static async logout(userId: string, rawRefreshToken?: string): Promise<void> {
    const db = getDatabase();
    const now = Date.now();
    if (rawRefreshToken) {
      const tokenHash = hashToken(rawRefreshToken);
      db.prepare('UPDATE refresh_sessions SET revoked_at = ? WHERE token_hash = ?').run(now, tokenHash);
    } else {
      db.prepare('UPDATE refresh_sessions SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL').run(now, userId);
    }

    AuditService.record({
      actorUid: userId,
      actorRole: 'user',
      action: 'USER_LOGOUT',
      reason: 'Refresh session revoked',
    });
  }

  static async generateDevPhoneCode(phoneNumber: string): Promise<{ verificationId: string; code: string; isSimulated: boolean }> {
    if (!env.ALLOW_DEV_PHONE_OTP) {
      throw new AppError('Simulated SMS OTP is disabled. A production SMS provider must be configured.', 403, 'OTP_PROVIDER_UNAVAILABLE');
    }

    const verificationId = `vcode_${crypto.randomUUID()}`;
    const code = '123456'; // Deterministic test OTP for development
    const expiresAt = Date.now() + 5 * 60 * 1000;

    devPhoneVerificationStore.set(verificationId, {
      phone: phoneNumber.trim(),
      code,
      expiresAt,
    });

    return {
      verificationId,
      code,
      isSimulated: true,
    };
  }

  static async verifyDevPhoneCode(verificationId: string, code: string): Promise<{ token: string; refreshToken: string; user: any }> {
    if (!env.ALLOW_DEV_PHONE_OTP) {
      throw new AppError('Simulated SMS OTP is disabled.', 403, 'OTP_PROVIDER_UNAVAILABLE');
    }

    const record = devPhoneVerificationStore.get(verificationId);
    if (!record || record.expiresAt <= Date.now() || record.code !== code.trim()) {
      throw new AppError('Invalid or expired verification code', 401, 'INVALID_CODE');
    }

    devPhoneVerificationStore.delete(verificationId);

    const db = getDatabase();
    let user = db.prepare('SELECT * FROM users WHERE phone = ?').get(record.phone) as UserRecord | undefined;

    if (!user) {
      // Auto-register driver on phone verification
      const res = await this.register({ phone: record.phone, role: 'driver' });
      return res;
    }

    AuditService.record({
      actorUid: user.id,
      actorRole: user.role,
      riderId: user.role === 'driver' ? user.id : null,
      action: 'USER_LOGIN_OTP',
      reason: 'Development phone verification succeeded',
    });

    return this.createAuthSession(user);
  }

  static async bootstrapAdmin(data: { email: string; password?: string; secret: string }): Promise<any> {
    if (data.secret !== env.ADMIN_BOOTSTRAP_SECRET) {
      throw new AppError('Invalid administrator bootstrap secret', 403, 'FORBIDDEN');
    }

    const db = getDatabase();
    const email = data.email.trim().toLowerCase();
    const password = data.password || 'AdminPassword123!';
    const passwordHash = await hashPassword(password);
    const now = Date.now();

    const existing = db.prepare('SELECT * FROM users WHERE email = ?').get(email) as UserRecord | undefined;

    if (existing) {
      db.prepare(`
        UPDATE users SET role = 'admin', password_hash = ?, updated_at = ? WHERE id = ?
      `).run(passwordHash, now, existing.id);

      AuditService.record({
        actorUid: existing.id,
        actorRole: 'admin',
        action: 'ADMIN_PROMOTED',
        reason: 'Administrator bootstrap promote',
      });

      return {
        id: existing.id,
        email: existing.email,
        role: 'admin',
        message: 'Admin account updated',
      };
    }

    const userId = `admin_${crypto.randomUUID()}`;
    db.prepare(`
      INSERT INTO users (id, email, phone, password_hash, role, account_status, created_at, updated_at)
      VALUES (?, ?, NULL, ?, 'admin', 'active', ?, ?)
    `).run(userId, email, passwordHash, now, now);

    AuditService.record({
      actorUid: userId,
      actorRole: 'admin',
      action: 'ADMIN_BOOTSTRAPPED',
      reason: 'Administrator bootstrap creation',
    });

    return {
      id: userId,
      email,
      role: 'admin',
      message: 'Admin account created successfully',
    };
  }

  private static createAuthSession(user: UserRecord): { token: string; refreshToken: string; user: any } {
    const db = getDatabase();
    const rawRefreshToken = generateRandomToken(40);
    const tokenHash = hashToken(rawRefreshToken);
    const sessionId = `ses_${crypto.randomUUID()}`;
    const now = Date.now();
    const expiresAt = now + env.REFRESH_TOKEN_EXPIRES_DAYS * 24 * 60 * 60 * 1000;

    db.prepare(`
      INSERT INTO refresh_sessions (id, user_id, token_hash, expires_at, created_at)
      VALUES (?, ?, ?, ?, ?)
    `).run(sessionId, user.id, tokenHash, expiresAt, now);

    const accessToken = generateAccessToken({
      userId: user.id,
      email: user.email,
      phone: user.phone,
      role: user.role,
    });

    return {
      token: accessToken,
      refreshToken: rawRefreshToken,
      user: {
        id: user.id,
        email: user.email,
        phone: user.phone,
        role: user.role,
        accountStatus: user.account_status,
      },
    };
  }
}
