import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { getDatabase, closeDatabase } from '../src/db/database.js';

describe('Auth Module API', () => {
  let app: any;

  beforeEach(() => {
    // In-memory test database
    getDatabase(':memory:');
    app = createApp();
  });

  afterEach(() => {
    closeDatabase();
  });

  it('registers a new driver account successfully', async () => {
    const res = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'testdriver@example.com',
        password: 'Password123!',
        role: 'driver',
      });

    expect(res.status).toBe(201);
    expect(res.body.success).toBe(true);
    expect(res.body.data.token).toBeDefined();
    expect(res.body.data.refreshToken).toBeDefined();
    expect(res.body.data.user.email).toBe('testdriver@example.com');
    expect(res.body.data.user.role).toBe('driver');
  });

  it('rejects duplicate email registration', async () => {
    await request(app)
      .post('/api/auth/register')
      .send({
        email: 'duplicate@example.com',
        password: 'Password123!',
      });

    const res = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'duplicate@example.com',
        password: 'Password123!',
      });

    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('EMAIL_EXISTS');
  });

  it('rejects short passwords', async () => {
    const res = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'shortpass@example.com',
        password: '123',
      });

    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('logs in with valid password', async () => {
    await request(app)
      .post('/api/auth/register')
      .send({
        email: 'login@example.com',
        password: 'ValidPassword123!',
      });

    const res = await request(app)
      .post('/api/auth/login')
      .send({
        email: 'login@example.com',
        password: 'ValidPassword123!',
      });

    expect(res.status).toBe(200);
    expect(res.body.data.token).toBeDefined();
    expect(res.body.data.refreshToken).toBeDefined();
  });

  it('rejects invalid password', async () => {
    await request(app)
      .post('/api/auth/register')
      .send({
        email: 'wrongpass@example.com',
        password: 'ValidPassword123!',
      });

    const res = await request(app)
      .post('/api/auth/login')
      .send({
        email: 'wrongpass@example.com',
        password: 'WrongPassword!',
      });

    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('INVALID_CREDENTIALS');
  });

  it('rotates refresh token and returns new session', async () => {
    const regRes = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'refresh@example.com',
        password: 'Password123!',
      });

    const originalRefresh = regRes.body.data.refreshToken;

    const refreshRes = await request(app)
      .post('/api/auth/refresh')
      .send({ refreshToken: originalRefresh });

    expect(refreshRes.status).toBe(200);
    expect(refreshRes.body.data.token).toBeDefined();
    expect(refreshRes.body.data.refreshToken).not.toBe(originalRefresh);

    // Old refresh token must now be rejected
    const replayRes = await request(app)
      .post('/api/auth/refresh')
      .send({ refreshToken: originalRefresh });

    expect(replayRes.status).toBe(401);
  });

  it('revokes session on logout', async () => {
    const regRes = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'logout@example.com',
        password: 'Password123!',
      });

    const token = regRes.body.data.token;
    const refreshToken = regRes.body.data.refreshToken;

    const logoutRes = await request(app)
      .post('/api/auth/logout')
      .set('Authorization', `Bearer ${token}`)
      .send({ refreshToken });

    expect(logoutRes.status).toBe(200);

    const refreshRes = await request(app)
      .post('/api/auth/refresh')
      .send({ refreshToken });

    expect(refreshRes.status).toBe(401);
  });

  it('supports simulated dev phone OTP', async () => {
    const phoneRes = await request(app)
      .post('/api/auth/phone-code')
      .send({ phoneNumber: '+15555550100' });

    expect(phoneRes.status).toBe(200);
    expect(phoneRes.body.data.verificationId).toBeDefined();
    expect(phoneRes.body.data.code).toBe('123456');

    const verifyRes = await request(app)
      .post('/api/auth/verify-phone-code')
      .send({
        verificationId: phoneRes.body.data.verificationId,
        code: '123456',
      });

    expect(verifyRes.status).toBe(200);
    expect(verifyRes.body.data.token).toBeDefined();
    expect(verifyRes.body.data.user.phone).toBe('+15555550100');
  });

  it('rejects access to /api/auth/me without token', async () => {
    const res = await request(app).get('/api/auth/me');
    expect(res.status).toBe(401);
  });

  it('returns profile on /api/auth/me with valid token', async () => {
    const regRes = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'me@example.com',
        password: 'Password123!',
      });

    const res = await request(app)
      .get('/api/auth/me')
      .set('Authorization', `Bearer ${regRes.body.data.token}`);

    expect(res.status).toBe(200);
    expect(res.body.data.user.email).toBe('me@example.com');
  });
});
