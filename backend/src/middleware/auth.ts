import { Request, Response, NextFunction } from 'express';
import { verifyAccessToken, AccessTokenPayload } from '../utils/crypto.js';
import { getDatabase } from '../db/database.js';

export interface AuthenticatedUser {
  id: string;
  email: string | null;
  phone: string | null;
  role: 'driver' | 'admin';
  accountStatus: string;
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthenticatedUser;
    }
  }
}

export function authenticate(req: Request, res: Response, next: NextFunction): void {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({
      success: false,
      error: {
        code: 'UNAUTHENTICATED',
        message: 'Authorization token is required',
      },
    });
    return;
  }

  const token = authHeader.substring(7).trim();
  try {
    const payload = verifyAccessToken(token);
    const db = getDatabase();
    const user = db.prepare('SELECT id, email, phone, role, account_status as accountStatus FROM users WHERE id = ?').get(payload.userId) as AuthenticatedUser | undefined;

    if (!user) {
      res.status(401).json({
        success: false,
        error: {
          code: 'USER_NOT_FOUND',
          message: 'Authenticated user no longer exists',
        },
      });
      return;
    }

    if (user.accountStatus === 'suspended') {
      res.status(403).json({
        success: false,
        error: {
          code: 'ACCOUNT_SUSPENDED',
          message: 'Account has been suspended',
        },
      });
      return;
    }

    req.user = user;
    next();
  } catch (error) {
    res.status(401).json({
      success: false,
      error: {
        code: 'INVALID_TOKEN',
        message: 'Invalid or expired access token',
      },
    });
  }
}

export function requireRole(allowedRoles: ('driver' | 'admin')[]) {
  return (req: Request, res: Response, next: NextFunction): void => {
    if (!req.user) {
      res.status(401).json({
        success: false,
        error: {
          code: 'UNAUTHENTICATED',
          message: 'Authentication required',
        },
      });
      return;
    }

    if (!allowedRoles.includes(req.user.role)) {
      res.status(403).json({
        success: false,
        error: {
          code: 'FORBIDDEN',
          message: `Access denied. Requires one of: ${allowedRoles.join(', ')}`,
        },
      });
      return;
    }

    next();
  };
}

export const requireAdmin = requireRole(['admin']);
