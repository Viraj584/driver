import test from 'node:test';
import assert from 'node:assert/strict';
import { evaluateDemoRisk, isDemoRiskEvent } from '../src/risk-policy.ts';

test('normal event is zero risk and active', () => {
  assert.deepEqual(evaluateDemoRisk('NORMAL_TELEMETRY', 'ACTIVE'), {
    score: 0,
    reasons: [],
    status: 'ACTIVE',
    verificationRequired: false,
    reviewRequired: false,
  });
});

test('device change alone does not trigger a punitive state', () => {
  const result = evaluateDemoRisk('DEVICE_CHANGE', 'ACTIVE');
  assert.equal(result.score, 0.3);
  assert.equal(result.status, 'ACTIVE');
  assert.equal(result.reviewRequired, false);
});

test('uncertain GPS is a weak signal', () => {
  const result = evaluateDemoRisk('GPS_JUMP_POOR_ACCURACY', 'ACTIVE');
  assert.equal(result.score, 0.05);
  assert.deepEqual(result.reasons, ['GPS_UNCERTAIN']);
});

test('correlated handoff requests step-up and preserves server policy', () => {
  const result = evaluateDemoRisk('POSSIBLE_HANDOFF', 'ACTIVE');
  assert.equal(result.score, 0.65);
  assert.equal(result.status, 'LIVENESS_PENDING');
  assert.equal(result.verificationRequired, true);
  assert.equal(result.reviewRequired, false);
});

test('restricted state is never downgraded by telemetry', () => {
  assert.equal(evaluateDemoRisk('NORMAL_TELEMETRY', 'RESTRICTED').status, 'RESTRICTED');
});

test('normal telemetry does not clear a pending challenge', () => {
  assert.equal(evaluateDemoRisk('NORMAL_TELEMETRY', 'LIVENESS_PENDING').status, 'LIVENESS_PENDING');
});

test('rejects unknown event labels', () => {
  assert.equal(isDemoRiskEvent('NORMAL_TELEMETRY'), true);
  assert.equal(isDemoRiskEvent({ event: 'NORMAL_TELEMETRY' }), false);
});
