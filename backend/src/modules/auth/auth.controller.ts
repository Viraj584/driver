import { Router, Request, Response, NextFunction } from 'express';
import { AuthService } from './auth.service.js';
import { validate } from '../../middleware/validate.js';
import { authenticate } from '../../middleware/auth.js';
import { rateLimiter } from '../../middleware/rateLimiter.js';
import {
  registerSchema,
  loginSchema,
  refreshSchema,
  logoutSchema,
  phoneCodeSchema,
  verifyPhoneCodeSchema,
  bootstrapAdminSchema,
} from './auth.schemas.js';

export const authRouter = Router();

const authLimiter = rateLimiter({ maxRequests: 20 });

authRouter.post(
  '/register',
  authLimiter,
  validate({ body: registerSchema }),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const result = await AuthService.register(req.body);
      res.status(201).json({ success: true, data: result });
    } catch (err) {
      next(err);
    }
  }
);

authRouter.post(
  '/login',
  authLimiter,
  validate({ body: loginSchema }),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const result = await AuthService.login(req.body);
      res.status(200).json({ success: true, data: result });
    } catch (err) {
      next(err);
    }
  }
);

authRouter.post(
  '/refresh',
  validate({ body: refreshSchema }),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const result = await AuthService.refresh(req.body.refreshToken);
      res.status(200).json({ success: true, data: result });
    } catch (err) {
      next(err);
    }
  }
);

authRouter.post(
  '/logout',
  authenticate,
  validate({ body: logoutSchema }),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      await AuthService.logout(req.user!.id, req.body.refreshToken);
      res.status(200).json({ success: true, data: { loggedOut: true } });
    } catch (err) {
      next(err);
    }
  }
);

authRouter.get(
  '/me',
  authenticate,
  async (req: Request, res: Response) => {
    res.status(200).json({
      success: true,
      data: {
        user: req.user,
      },
    });
  }
);

authRouter.post(
  '/phone-code',
  authLimiter,
  validate({ body: phoneCodeSchema }),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const result = await AuthService.generateDevPhoneCode(req.body.phoneNumber);
      res.status(200).json({ success: true, data: result });
    } catch (err) {
      next(err);
    }
  }
);

authRouter.post(
  '/verify-phone-code',
  authLimiter,
  validate({ body: verifyPhoneCodeSchema }),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const result = await AuthService.verifyDevPhoneCode(req.body.verificationId, req.body.code);
      res.status(200).json({ success: true, data: result });
    } catch (err) {
      next(err);
    }
  }
);

authRouter.post(
  '/bootstrap-admin',
  validate({ body: bootstrapAdminSchema }),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const result = await AuthService.bootstrapAdmin(req.body);
      res.status(200).json({ success: true, data: result });
    } catch (err) {
      next(err);
    }
  }
);
