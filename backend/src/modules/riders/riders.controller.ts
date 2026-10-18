import { Router, Request, Response, NextFunction } from 'express';
import { RidersService } from './riders.service.js';
import { authenticate } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { deviceEnrollmentSchema, deviceParamSchema } from './riders.schemas.js';

export const ridersRouter = Router();

ridersRouter.use(authenticate);

ridersRouter.get('/me', (req: Request, res: Response, next: NextFunction) => {
  try {
    const profile = RidersService.getProfile(req.user!.id);
    res.status(200).json({ success: true, data: { driver: profile } });
  } catch (err) {
    next(err);
  }
});

ridersRouter.post('/ensure', (req: Request, res: Response, next: NextFunction) => {
  try {
    const result = RidersService.ensureProfile(req.user!.id);
    res.status(200).json({ success: true, data: result });
  } catch (err) {
    next(err);
  }
});

ridersRouter.post(
  '/devices',
  validate({ body: deviceEnrollmentSchema }),
  (req: Request, res: Response, next: NextFunction) => {
    try {
      const result = RidersService.requestDeviceEnrollment(req.user!.id, req.body.platform);
      res.status(201).json({ success: true, data: result });
    } catch (err) {
      next(err);
    }
  }
);

ridersRouter.post(
  '/devices/:id/revoke',
  validate({ params: deviceParamSchema }),
  (req: Request, res: Response, next: NextFunction) => {
    try {
      const result = RidersService.revokeDevice(req.user!.id, req.params.id);
      res.status(200).json({ success: true, data: result });
    } catch (err) {
      next(err);
    }
  }
);
