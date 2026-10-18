import { z } from 'zod';

export const deliveryParamSchema = z.object({
  id: z.string().min(1),
});
