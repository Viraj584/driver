import dotenv from 'dotenv';
import path from 'path';
import { z } from 'zod';

dotenv.config({ path: path.resolve(process.cwd(), '.env') });

const envSchema = z.object({
  PORT: z.string().default('3000').transform(val => parseInt(val, 10)),
  HOST: z.string().default('0.0.0.0'),
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  DATABASE_PATH: z.string().default('./trust_juggler.db'),
  JWT_SECRET: z.string().min(16).default('trust_juggler_super_secure_jwt_secret_dev_32char_key!'),
  JWT_EXPIRES_IN: z.string().default('15m'),
  REFRESH_TOKEN_EXPIRES_DAYS: z.string().default('7').transform(val => parseInt(val, 10)),
  CORS_ORIGIN: z.string().default('*'),
  ALLOW_DEV_PHONE_OTP: z.string().default('true').transform(val => val === 'true'),
  ADMIN_BOOTSTRAP_SECRET: z.string().default('trust_juggler_admin_bootstrap_secret_2026'),
});

export const env = envSchema.parse(process.env);
