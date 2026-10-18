import { Router, Request, Response, NextFunction } from 'express';
import { ChallengesService } from './challenges.service.js';
import { authenticate } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { resolveChallengeSchema, challengeParamSchema } from './challenges.schemas.js';

export const challengesRouter = Router();

challengesRouter.use(authenticate);

challengesRouter.get('/', (req: Request, res: Response, next: NextFunction) => {
  try {
    const challenges = ChallengesService.getPendingChallenges(req.user!.id);
    res.status(200).json({ success: true, data: { challenges } });
  } catch (err) {
    next(err);
  }
});

challengesRouter.post(
  '/:id/resolve',
  validate({ params: challengeParamSchema, body: resolveChallengeSchema }),
  (req: Request, res: Response, next: NextFunction) => {
    try {
      const result = ChallengesService.resolveChallenge(
        req.user!.id,
        req.params.id,
        req.body.passed
      );
      res.status(200).json({ success: true, data: result });
    } catch (err) {
      next(err);
    }
  }
);

challengesRouter.post(
  '/resolve',
  validate({ body: resolveChallengeSchema }),
  (req: Request, res: Response, next: NextFunction) => {
    try {
      const targetId = req.body.requestId;
      if (!targetId) {
        res.status(400).json({
          success: false,
          error: { code: 'BAD_REQUEST', message: 'requestId is required' },
        });
        return;
      }
      const result = ChallengesService.resolveChallenge(
        req.user!.id,
        targetId,
        req.body.passed
      );
      res.status(200).json({ success: true, data: result });
    } catch (err) {
      next(err);
    }
  }
);
