import { Router, Request, Response, NextFunction } from 'express';
import { RiskService } from './risk.service.js';
import { authenticate } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { rateLimiter } from '../../middleware/rateLimiter.js';
import { submitRiskEventSchema } from './risk.schemas.js';

export const riskRouter = Router();

riskRouter.use(authenticate);

const riskLimiter = rateLimiter({ maxRequests: 60 });

riskRouter.post(
  '/events',
  riskLimiter,
  validate({ body: submitRiskEventSchema }),
  (req: Request, res: Response, next: NextFunction) => {
    try {
      const result = RiskService.submitRiskEvent(req.user!.id, req.body);
      res.status(200).json({ success: true, data: result });
    } catch (err) {
      next(err);
    }
  }
);

riskRouter.get('/events', (req: Request, res: Response, next: NextFunction) => {
  try {
    const history = RiskService.getHistory(req.user!.id);
    res.status(200).json({ success: true, data: history });
  } catch (err) {
    next(err);
  }
});

riskRouter.get('/state', (req: Request, res: Response, next: NextFunction) => {
  try {
    const state = RiskService.getState(req.user!.id);
    res.status(200).json({ success: true, data: state });
  } catch (err) {
    next(err);
  }
});
