import express, { Express, Request, Response } from 'express';
import cors from 'cors';
import { env } from './config/env.js';
import { errorHandler } from './middleware/errorHandler.js';
import { authRouter } from './modules/auth/auth.controller.js';
import { ridersRouter } from './modules/riders/riders.controller.js';
import { riskRouter } from './modules/risk/risk.controller.js';
import { challengesRouter } from './modules/challenges/challenges.controller.js';
import { deliveriesRouter } from './modules/deliveries/deliveries.controller.js';
import { adminRouter } from './modules/admin/admin.controller.js';
import { authenticate } from './middleware/auth.js';
import { RidersService } from './modules/riders/riders.service.js';

export function createApp(): Express {
  const app = express();

  // Middleware
  app.use(cors({
    origin: env.CORS_ORIGIN === '*' ? true : env.CORS_ORIGIN,
    credentials: true,
  }));
  app.use(express.json({ limit: '1mb' }));
  app.use(express.urlencoded({ extended: true, limit: '1mb' }));

  // Health check
  app.get('/api/health', (req: Request, res: Response) => {
    res.status(200).json({
      success: true,
      data: {
        status: 'UP',
        timestamp: new Date().toISOString(),
        version: '1.0.0',
        environment: env.NODE_ENV,
      },
    });
  });

  // Legacy external profile compatibility endpoint: GET /api/v1/driver/me
  app.get('/api/v1/driver/me', authenticate, (req: Request, res: Response, next) => {
    try {
      const profile = RidersService.getProfile(req.user!.id);
      res.status(200).json({
        driver: {
          accountStatus: profile.accountStatus,
          registrationStatus: profile.registrationStatus,
          identityVerificationStatus: profile.identityVerificationStatus,
          deviceEnrollmentStatus: profile.deviceEnrollmentStatus,
          requiredDocumentsStatus: 'verified',
          trainingStatus: 'complete',
        },
      });
    } catch (err) {
      next(err);
    }
  });

  // API Routes
  app.use('/api/auth', authRouter);
  app.use('/api/riders', ridersRouter);
  app.use('/api/risk', riskRouter);
  app.use('/api/challenges', challengesRouter);
  app.use('/api/deliveries', deliveriesRouter);
  app.use('/api/admin', adminRouter);

  // 404 handler
  app.use((req: Request, res: Response) => {
    res.status(404).json({
      success: false,
      error: {
        code: 'NOT_FOUND',
        message: `Route ${req.method} ${req.originalUrl} not found`,
      },
    });
  });

  // Centralized error handler
  app.use(errorHandler);

  return app;
}
