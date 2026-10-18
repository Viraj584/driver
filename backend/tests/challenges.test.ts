import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { getDatabase, closeDatabase } from '../src/db/database.js';

describe('Challenges API', () => {
  let app: any;
  let driverToken: string;

  beforeEach(async () => {
    getDatabase(':memory:');
    app = createApp();

    const regRes = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'challenge_driver@example.com',
        password: 'Password123!',
        role: 'driver',
      });
    driverToken = regRes.body.data.token;

    // Trigger challenge
    await request(app)
      .post('/api/risk/events')
      .set('Authorization', `Bearer ${driverToken}`)
      .send({
        requestId: 'req_ch_trigger_123',
        eventType: 'POSSIBLE_HANDOFF',
        source: 'SIMULATOR',
      });
  });

  afterEach(() => {
    closeDatabase();
  });

  it('lists pending challenges', async () => {
    const res = await request(app)
      .get('/api/challenges')
      .set('Authorization', `Bearer ${driverToken}`);

    expect(res.status).toBe(200);
    expect(res.body.data.challenges.length).toBe(1);
    expect(res.body.data.challenges[0].status).toBe('PENDING');
  });

  it('resolves demo challenge without granting unilateral account clearance', async () => {
    const res = await request(app)
      .post('/api/challenges/req_ch_trigger_123/resolve')
      .set('Authorization', `Bearer ${driverToken}`)
      .send({ passed: true });

    expect(res.status).toBe(200);
    expect(res.body.data.recorded).toBe(true);
    // Note: client simulated check does not arbitrarily clear real account status
    expect(res.body.data.resultingStatus).toBe('LIVENESS_PENDING');

    // Confirm state has reviewRequired = true
    const stateRes = await request(app)
      .get('/api/risk/state')
      .set('Authorization', `Bearer ${driverToken}`);

    expect(stateRes.body.data.riskStatus).toBe('LIVENESS_PENDING');
    expect(stateRes.body.data.reviewRequired).toBe(true);
  });
});
