import { Router, Request, Response, NextFunction } from 'express';
import { DeliveriesService } from './deliveries.service.js';
import { authenticate } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { deliveryParamSchema } from './deliveries.schemas.js';

export const deliveriesRouter = Router();

deliveriesRouter.use(authenticate);

deliveriesRouter.get('/', (req: Request, res: Response, next: NextFunction) => {
  try {
    const list = DeliveriesService.listDeliveries(req.user!.id);
    res.status(200).json({ success: true, data: { deliveries: list } });
  } catch (err) {
    next(err);
  }
});

deliveriesRouter.post(
  '/:id/accept',
  validate({ params: deliveryParamSchema }),
  (req: Request, res: Response, next: NextFunction) => {
    try {
      const result = DeliveriesService.acceptDelivery(req.user!.id, req.params.id);
      res.status(200).json({ success: true, data: result });
    } catch (err) {
      next(err);
    }
  }
);

deliveriesRouter.post(
  '/:id/complete',
  validate({ params: deliveryParamSchema }),
  (req: Request, res: Response, next: NextFunction) => {
    try {
      const result = DeliveriesService.completeDelivery(req.user!.id, req.params.id);
      res.status(200).json({ success: true, data: result });
    } catch (err) {
      next(err);
    }
  }
);
