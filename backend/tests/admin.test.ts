import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { getDatabase, closeDatabase } from '../src/db/database.js';

describe('Admin Module API & Workflows', () => {
  let app: any;
  let adminToken: string;
  let driverToken: string;
  let driverId: string;

  beforeEach(async () => {
    getDatabase(':memory:');
    app = createApp();

    // 1. Create admin via bootstrap
    const bootRes = await request(app)
      .post('/api/auth/bootstrap-admin')
      .send({
        email: 'admin@example.com',
        password: 'AdminPassword123!',
        secret: 'trust_juggler_admin_bootstrap_secret_2026',
      });

    const loginRes = await request(app)
      .post('/api/auth/login')
      .send({
        email: 'admin@example.com',
        password: 'AdminPassword123!',
      });
    adminToken = loginRes.body.data.token;

    // 2. Create driver
    const driverRes = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'pending_driver@example.com',
        password: 'Password123!',
        role: 'driver',
      });
    driverToken = driverRes.body.data.token;
    driverId = driverRes.body.data.user.id;

    // Trigger step-up to put rider in LIVENESS_PENDING
    await request(app)
      .post('/api/risk/events')
      .set('Authorization', `Bearer ${driverToken}`)
      .send({
        requestId: 'req_admin_test_1',
        eventType: 'POSSIBLE_HANDOFF',
        source: 'SIMULATOR',
      });
  });

  afterEach(() => {
    closeDatabase();
  });

  it('rejects non-admin from accessing admin routes', async () => {
    const res = await request(app)
      .get('/api/admin/riders')
      .set('Authorization', `Bearer ${driverToken}`);

    expect(res.status).toBe(403);
  });

  it('admin can list riders', async () => {
    const res = await request(app)
      .get('/api/admin/riders')
      .set('Authorization', `Bearer ${adminToken}`);

    expect(res.status).toBe(200);
    expect(res.body.data.riders.length).toBeGreaterThan(0);
    const rider = res.body.data.riders.find((r: any) => r.id === driverId);
    expect(rider.riskStatus).toBe('LIVENESS_PENDING');
  });

  it('admin approves pending rider session and returns to ACTIVE', async () => {
    const res = await request(app)
      .post(`/api/admin/riders/${driverId}/review`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({
        action: 'APPROVE_SESSION',
        reason: 'Verified driver identity via supervisor video call',
      });

    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('ACTIVE');

    // Confirm rider profile is now ACTIVE
    const riderRes = await request(app)
      .get('/api/admin/riders')
      .set('Authorization', `Bearer ${adminToken}`);

    const rider = riderRes.body.data.riders.find((r: any) => r.id === driverId);
    expect(rider.riskStatus).toBe('ACTIVE');
    expect(rider.reviewRequired).toBe(false);
  });

  it('admin restricts account when policy violation confirmed', async () => {
    const res = await request(app)
      .post(`/api/admin/riders/${driverId}/review`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({
        action: 'RESTRICT_ACCOUNT',
        reason: 'Confirmed unauthorized account sharing on device',
      });

    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('RESTRICTED');
  });

  it('admin reviews device enrollment', async () => {
    // Rider requests device
    const devRes = await request(app)
      .post('/api/riders/devices')
      .set('Authorization', `Bearer ${driverToken}`)
      .send({ platform: 'android' });

    const deviceId = devRes.body.data.deviceEnrollmentId;

    // Admin approves device
    const approveRes = await request(app)
      .post(`/api/admin/devices/${deviceId}/review`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({
        driverUid: driverId,
        approve: true,
      });

    expect(approveRes.status).toBe(200);
    expect(approveRes.body.data.status).toBe('active');
  });

  it('admin can inspect global audit logs', async () => {
    const res = await request(app)
      .get('/api/admin/audit-logs')
      .set('Authorization', `Bearer ${adminToken}`);

    expect(res.status).toBe(200);
    expect(res.body.data.events.length).toBeGreaterThan(0);
  });
});
