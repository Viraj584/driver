import { z } from 'zod';

export const resolveChallengeSchema = z.object({
  requestId: z.string().optional(),
  passed: z.boolean(),
});

export const challengeParamSchema = z.object({
  id: z.string().min(1),
});
