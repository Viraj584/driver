import bcrypt from 'bcrypt';
import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { APP_CONSTANTS } from '../config/constants.js';

export interface AccessTokenPayload {
  userId: string;
  email?: string | null;
  phone?: string | null;
  role: 'driver' | 'admin';
}

export async function hashPassword(plain: string): Promise<string> {
  return bcrypt.hash(plain, APP_CONSTANTS.PASSWORD_SALT_ROUNDS);
}

export async function verifyPassword(plain: string, hash: string): Promise<boolean> {
  return bcrypt.compare(plain, hash);
}

export function generateRandomToken(byteLength = 32): string {
  return crypto.randomBytes(byteLength).toString('hex');
}

export function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}

export function generateAccessToken(payload: AccessTokenPayload): string {
  return jwt.sign(payload, env.JWT_SECRET, {
    expiresIn: env.JWT_EXPIRES_IN as any,
    issuer: APP_CONSTANTS.JWT_ISSUER,
    audience: APP_CONSTANTS.JWT_AUDIENCE,
  });
}

export function verifyAccessToken(token: string): AccessTokenPayload {
  const decoded = jwt.verify(token, env.JWT_SECRET, {
    issuer: APP_CONSTANTS.JWT_ISSUER,
    audience: APP_CONSTANTS.JWT_AUDIENCE,
  }) as AccessTokenPayload & jwt.JwtPayload;

  return {
    userId: decoded.userId,
    email: decoded.email,
    phone: decoded.phone,
    role: decoded.role,
  };
}
