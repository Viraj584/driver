import { z } from 'zod';
import { validDemoRiskEvents } from './risk.policy.js';

export const submitRiskEventSchema = z.object({
  requestId: z.string().regex(/^[A-Za-z0-9_-]{8,96}$/, 'Request ID must be 8-96 characters and alphanumeric, underscore or hyphen'),
  eventType: z.enum(validDemoRiskEvents as [string, ...string[]]),
  source: z.enum(['SIMULATOR', 'APP']).default('SIMULATOR'),
});
