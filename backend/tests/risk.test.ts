import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { getDatabase, closeDatabase } from '../src/db/database.js';

describe('Risk Engine API', () => {
  let app: any;
  let driverToken: string;

  beforeEach(async () => {
    getDatabase(':memory:');
    app = createApp();

    const regRes = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'risk_driver@example.com',
        password: 'Password123!',
        role: 'driver',
      });
    driverToken = regRes.body.data.token;
  });

  afterEach(() => {
    closeDatabase();
  });

  it('normal telemetry produces 0 risk and keeps rider ACTIVE', async () => {
    const res = await request(app)
      .post('/api/risk/events')
      .set('Authorization', `Bearer ${driverToken}`)
      .send({
        requestId: 'req_normal_12345',
        eventType: 'NORMAL_TELEMETRY',
        source: 'SIMULATOR',
      });

    expect(res.status).toBe(200);
    expect(res.body.data.score).toBe(0);
    expect(res.body.data.status).toBe('ACTIVE');
    expect(res.body.data.verificationRequired).toBe(false);
  });

  it('device change produces 0.3 risk and does not automatically block rider', async () => {
    const res = await request(app)
      .post('/api/risk/events')
      .set('Authorization', `Bearer ${driverToken}`)
      .send({
        requestId: 'req_devchange_12345',
        eventType: 'DEVICE_CHANGE',
        source: 'SIMULATOR',
      });

    expect(res.status).toBe(200);
    expect(res.body.data.score).toBe(0.3);
    expect(res.body.data.status).toBe('ACTIVE');
    expect(res.body.data.verificationRequired).toBe(false);
  });

  it('poor GPS accuracy produces lower risk than verified GPS jump', async () => {
    const poorRes = await request(app)
      .post('/api/risk/events')
      .set('Authorization', `Bearer ${driverToken}`)
      .send({
        requestId: 'req_gps_poor_12345',
        eventType: 'GPS_JUMP_POOR_ACCURACY',
        source: 'SIMULATOR',
      });

    const jumpRes = await request(app)
      .post('/api/risk/events')
      .set('Authorization', `Bearer ${driverToken}`)
      .send({
        requestId: 'req_gps_jump_12345',
        eventType: 'GPS_JUMP',
        source: 'SIMULATOR',
      });

    expect(poorRes.body.data.score).toBe(0.05);
    expect(jumpRes.body.data.score).toBe(0.35);
  });

  it('possible handoff triggers LIVENESS_PENDING and step-up challenge', async () => {
    const res = await request(app)
      .post('/api/risk/events')
      .set('Authorization', `Bearer ${driverToken}`)
      .send({
        requestId: 'req_handoff_12345',
        eventType: 'POSSIBLE_HANDOFF',
        source: 'SIMULATOR',
      });

    expect(res.status).toBe(200);
    expect(res.body.data.score).toBe(0.65);
    expect(res.body.data.status).toBe('LIVENESS_PENDING');
    expect(res.body.data.verificationRequired).toBe(true);

    // Verify challenge created
    const challengesRes = await request(app)
      .get('/api/challenges')
      .set('Authorization', `Bearer ${driverToken}`);

    expect(challengesRes.status).toBe(200);
    expect(challengesRes.body.data.challenges.length).toBeGreaterThan(0);
    expect(challengesRes.body.data.challenges[0].requestId).toBe('req_handoff_12345');
  });

  it('provides idempotent results on duplicate requestId', async () => {
    const firstRes = await request(app)
      .post('/api/risk/events')
      .set('Authorization', `Bearer ${driverToken}`)
      .send({
        requestId: 'req_idempotent_12345',
        eventType: 'DEVICE_CHANGE',
        source: 'SIMULATOR',
      });

    expect(firstRes.body.data.duplicate).toBe(false);

    const dupRes = await request(app)
      .post('/api/risk/events')
      .set('Authorization', `Bearer ${driverToken}`)
      .send({
        requestId: 'req_idempotent_12345',
        eventType: 'DEVICE_CHANGE',
        source: 'SIMULATOR',
      });

    expect(dupRes.status).toBe(200);
    expect(dupRes.body.data.duplicate).toBe(true);
    expect(dupRes.body.data.score).toBe(0.3);
  });

  it('rejects conflicting event types on same requestId', async () => {
    await request(app)
      .post('/api/risk/events')
      .set('Authorization', `Bearer ${driverToken}`)
      .send({
        requestId: 'req_conflict_12345',
        eventType: 'DEVICE_CHANGE',
        source: 'SIMULATOR',
      });

    const conflictRes = await request(app)
      .post('/api/risk/events')
      .set('Authorization', `Bearer ${driverToken}`)
      .send({
        requestId: 'req_conflict_12345',
        eventType: 'POSSIBLE_HANDOFF',
        source: 'SIMULATOR',
      });

    expect(conflictRes.status).toBe(409);
  });
});
