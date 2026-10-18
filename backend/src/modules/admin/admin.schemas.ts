import { z } from 'zod';

export const adminReviewRiderSchema = z.object({
  action: z.enum(['APPROVE_SESSION', 'RESTRICT_ACCOUNT']),
  reason: z.string().min(8, 'Reason must be at least 8 characters long').max(500),
  requestId: z.string().optional(),
});

export const adminReviewDeviceSchema = z.object({
  driverUid: z.string().min(1),
  approve: z.boolean(),
});

export const adminUpdateRegistrationSchema = z.object({
  registrationStatus: z.enum(['registration_pending', 'identity_pending', 'approved', 'rejected', 'suspended']),
});

export const idParamSchema = z.object({
  id: z.string().min(1),
});
