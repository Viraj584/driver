import { z } from 'zod';

export const registerSchema = z.object({
  email: z.string().email().optional(),
  phone: z.string().regex(/^\+[1-9]\d{1,14}$/, 'Must be E.164 phone format (e.g. +15555550100)').optional(),
  password: z.string().min(8, 'Password must be at least 8 characters long'),
  role: z.enum(['driver', 'admin']).default('driver'),
}).refine(data => data.email || data.phone, {
  message: 'Either email or phone is required',
  path: ['email'],
});

export const loginSchema = z.object({
  identifier: z.string().optional(),
  email: z.string().email().optional(),
  phone: z.string().optional(),
  password: z.string().min(1, 'Password is required'),
}).refine(data => data.identifier || data.email || data.phone, {
  message: 'Email or phone identifier is required',
  path: ['identifier'],
});

export const refreshSchema = z.object({
  refreshToken: z.string().min(1, 'Refresh token is required'),
});

export const logoutSchema = z.object({
  refreshToken: z.string().optional(),
});

export const phoneCodeSchema = z.object({
  phoneNumber: z.string().regex(/^\+[1-9]\d{1,14}$/, 'Must be E.164 phone format'),
});

export const verifyPhoneCodeSchema = z.object({
  verificationId: z.string().min(8),
  code: z.string().min(4).max(8),
});

export const bootstrapAdminSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  secret: z.string().min(8),
});
