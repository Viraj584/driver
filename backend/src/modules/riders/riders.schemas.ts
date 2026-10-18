import { z } from 'zod';

export const deviceEnrollmentSchema = z.object({
  platform: z.enum(['android', 'ios']),
});

export const deviceParamSchema = z.object({
  id: z.string().min(1),
});
