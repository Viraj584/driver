import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { getDatabase, closeDatabase } from '../src/db/database.js';

describe('Deliveries API & Risk Gating', () => {
  let app: any;
  let activeDriverToken: string;
  let pendingDriverToken: string;

  beforeEach(async () => {
    getDatabase(':memory:');
    app = createApp();

    // 1. Active driver
    const activeRes = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'active_driver@example.com',
        password: 'Password123!',
        role: 'driver',
      });
    activeDriverToken = activeRes.body.data.token;

    // 2. Pending driver (triggers handoff)
    const pendingRes = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'pending_driver@example.com',
        password: 'Password123!',
        role: 'driver',
      });
    pendingDriverToken = pendingRes.body.data.token;

    await request(app)
      .post('/api/risk/events')
      .set('Authorization', `Bearer ${pendingDriverToken}`)
      .send({
        requestId: 'req_pending_handoff',
        eventType: 'POSSIBLE_HANDOFF',
        source: 'SIMULATOR',
      });
  });

  afterEach(() => {
    closeDatabase();
  });

  it('lists seeded deliveries', async () => {
    const res = await request(app)
      .get('/api/deliveries')
      .set('Authorization', `Bearer ${activeDriverToken}`);

    expect(res.status).toBe(200);
    expect(res.body.data.deliveries.length).toBe(3);
    expect(res.body.data.deliveries[0].status).toBe('available');
  });

  it('allows active driver to accept available delivery', async () => {
    const res = await request(app)
      .post('/api/deliveries/TJ-DEMO-8492/accept')
      .set('Authorization', `Bearer ${activeDriverToken}`);

    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('assigned');
    expect(res.body.data.assignmentId).toBeDefined();

    // Verify delivery is now marked assigned
    const listRes = await request(app)
      .get('/api/deliveries')
      .set('Authorization', `Bearer ${activeDriverToken}`);

    const order = listRes.body.data.deliveries.find((d: any) => d.id === 'TJ-DEMO-8492');
    expect(order.status).toBe('assigned');
    expect(order.isAssignedToCurrentRider).toBe(true);
  });

  it('blocks driver with LIVENESS_PENDING from accepting delivery', async () => {
    const res = await request(app)
      .post('/api/deliveries/TJ-DEMO-8493/accept')
      .set('Authorization', `Bearer ${pendingDriverToken}`);

    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('VERIFICATION_PENDING');
  });

  it('rejects duplicate acceptance of already assigned delivery', async () => {
    // First driver claims TJ-DEMO-8494
    await request(app)
      .post('/api/deliveries/TJ-DEMO-8494/accept')
      .set('Authorization', `Bearer ${activeDriverToken}`);

    // Create another active driver
    const anotherRes = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'another_driver@example.com',
        password: 'Password123!',
        role: 'driver',
      });

    const secondAcceptRes = await request(app)
      .post('/api/deliveries/TJ-DEMO-8494/accept')
      .set('Authorization', `Bearer ${anotherRes.body.data.token}`);

    expect(secondAcceptRes.status).toBe(409);
  });

  it('allows assigned driver to complete delivery', async () => {
    await request(app)
      .post('/api/deliveries/TJ-DEMO-8492/accept')
      .set('Authorization', `Bearer ${activeDriverToken}`);

    const res = await request(app)
      .post('/api/deliveries/TJ-DEMO-8492/complete')
      .set('Authorization', `Bearer ${activeDriverToken}`);

    expect(res.status).toBe(200);
    expect(res.body.data.completed).toBe(true);
  });
});
