import { Router, Request, Response, NextFunction } from 'express';
import { AdminService } from './admin.service.js';
import { authenticate, requireAdmin } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { rateLimiter } from '../../middleware/rateLimiter.js';
import {
  adminReviewRiderSchema,
  adminReviewDeviceSchema,
  adminUpdateRegistrationSchema,
  idParamSchema,
} from './admin.schemas.js';

export const adminRouter = Router();

adminRouter.use(authenticate);
adminRouter.use(requireAdmin);

const adminLimiter = rateLimiter({ maxRequests: 30 });
adminRouter.use(adminLimiter);

adminRouter.get('/riders', (req: Request, res: Response, next: NextFunction) => {
  try {
    const list = AdminService.listRiders();
    res.status(200).json({ success: true, data: { riders: list } });
  } catch (err) {
    next(err);
  }
});

adminRouter.get('/risk-events', (req: Request, res: Response, next: NextFunction) => {
  try {
    const events = AdminService.getFleetRiskEvents();
    res.status(200).json({ success: true, data: { events } });
  } catch (err) {
    next(err);
  }
});

adminRouter.get('/audit-logs', (req: Request, res: Response, next: NextFunction) => {
  try {
    const events = AdminService.getFleetAuditLogs();
    res.status(200).json({ success: true, data: { events } });
  } catch (err) {
    next(err);
  }
});

adminRouter.post(
  '/riders/:id/review',
  validate({ params: idParamSchema, body: adminReviewRiderSchema }),
  (req: Request, res: Response, next: NextFunction) => {
    try {
      const result = AdminService.reviewRider(
        req.user!.id,
        req.params.id,
        req.body.action,
        req.body.reason,
        req.body.requestId
      );
      res.status(200).json({ success: true, data: result });
    } catch (err) {
      next(err);
    }
  }
);

adminRouter.post(
  '/devices/:id/review',
  validate({ params: idParamSchema, body: adminReviewDeviceSchema }),
  (req: Request, res: Response, next: NextFunction) => {
    try {
      const result = AdminService.reviewDevice(
        req.user!.id,
        req.body.driverUid,
        req.params.id,
        req.body.approve
      );
      res.status(200).json({ success: true, data: result });
    } catch (err) {
      next(err);
    }
  }
);

adminRouter.post(
  '/riders/:id/registration',
  validate({ params: idParamSchema, body: adminUpdateRegistrationSchema }),
  (req: Request, res: Response, next: NextFunction) => {
    try {
      const result = AdminService.updateRegistration(
        req.user!.id,
        req.params.id,
        req.body.registrationStatus
      );
      res.status(200).json({ success: true, data: result });
    } catch (err) {
      next(err);
    }
  }
);
