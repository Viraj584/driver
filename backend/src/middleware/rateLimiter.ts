import { Request, Response, NextFunction } from 'express';

interface RateLimitRecord {
  windowStart: number;
  count: number;
}

const rateLimitStore = new Map<string, RateLimitRecord>();

// Cleanup stale entries every 5 minutes
setInterval(() => {
  const now = Date.now();
  for (const [key, record] of rateLimitStore.entries()) {
    if (now - record.windowStart > 5 * 60 * 1000) {
      rateLimitStore.delete(key);
    }
  }
}, 5 * 60 * 1000);

export function rateLimiter(options: {
  windowMs?: number;
  maxRequests: number;
  keyGenerator?: (req: Request) => string;
}) {
  const windowMs = options.windowMs || 60 * 1000;
  const maxRequests = options.maxRequests;
  const keyGen = options.keyGenerator || (req => req.ip || req.socket.remoteAddress || 'unknown');

  return (req: Request, res: Response, next: NextFunction): void => {
    const key = `${req.baseUrl || req.path}:${keyGen(req)}`;
    const now = Date.now();
    const record = rateLimitStore.get(key);

    if (!record || now - record.windowStart > windowMs) {
      rateLimitStore.set(key, { windowStart: now, count: 1 });
      next();
      return;
    }

    if (record.count >= maxRequests) {
      res.status(429).json({
        success: false,
        error: {
          code: 'RATE_LIMIT_EXCEEDED',
          message: 'Too many requests. Please try again later.',
        },
      });
      return;
    }

    record.count += 1;
    next();
  };
}
