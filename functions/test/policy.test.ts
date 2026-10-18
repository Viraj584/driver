import test from 'node:test';
import assert from 'node:assert/strict';
import { assertValidPlatform, isAuthenticated, mayAdminister, mayStartRide } from '../src/policy.ts';

const approved = {
  role: 'driver',
  accountStatus: 'active',
  registrationStatus: 'approved' as const,
  identityVerificationStatus: 'verified',
  deviceEnrollmentStatus: 'enrolled',
};

test('only a server-issued true admin claim grants the admin policy', () => {
  assert.equal(mayAdminister({ admin: true }), true);
  assert.equal(mayAdminister({ admin: false }), false);
  assert.equal(mayAdminister({ role: 'admin', admin: 'true' }), false);
});

test('missing and malformed callable identities are unauthenticated', () => {
  assert.equal(isAuthenticated(undefined), false);
  assert.equal(isAuthenticated(''), false);
  assert.equal(isAuthenticated(42), false);
  assert.equal(isAuthenticated('firebase-uid'), true);
});

test('ride policy denies pending driver, missing device, or absent verification event', () => {
  assert.equal(mayStartRide({ ...approved, registrationStatus: 'registration_pending' }, true, 'event'), false);
  assert.equal(mayStartRide(approved, false, 'event'), false);
  assert.equal(mayStartRide(approved, true, null), false);
  assert.equal(mayStartRide(approved, true, 'event'), true);
});

test('device platform is constrained to supported app platforms', () => {
  assertValidPlatform('android');
  assertValidPlatform('ios');
  assert.throws(() => assertValidPlatform('phone-model'), /platform must be/);
});
