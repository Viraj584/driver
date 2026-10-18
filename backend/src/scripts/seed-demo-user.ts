import crypto from 'crypto';
import { getDatabase, closeDatabase } from '../db/database.js';
import { hashPassword } from '../utils/crypto.js';

async function seedDemoUser() {
  const email = process.env.DEMO_EMAIL ||
    (process.argv[2] && !process.argv[2].includes('=') ? process.argv[2] : null) ||
    process.argv.find(arg => arg.startsWith('email='))?.split('=')[1] ||
    'demo.driver@trustjuggler.internal';

  const password = process.env.DEMO_PASSWORD ||
    (process.argv[3] && !process.argv[3].includes('=') ? process.argv[3] : null) ||
    process.argv.find(arg => arg.startsWith('password='))?.split('=')[1] ||
    'DemoDriver123!';

  const phone = process.env.DEMO_PHONE ||
    process.argv.find(arg => arg.startsWith('phone='))?.split('=')[1] ||
    '+15551234567';

  console.log(`[Demo Seed] Seeding presentation demo driver user: ${email}...`);

  const db = getDatabase();
  const normalizedEmail = email.trim().toLowerCase();
  const passwordHash = await hashPassword(password);
  const now = Date.now();

  try {
    const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(normalizedEmail) as { id: string } | undefined;

    let userId: string;

    if (existing) {
      userId = existing.id;
      db.prepare(`
        UPDATE users
        SET password_hash = ?, phone = ?, role = 'driver', account_status = 'active', updated_at = ?
        WHERE id = ?
      `).run(passwordHash, phone, now, userId);

      db.prepare(`
        INSERT INTO rider_profiles (
          user_id, registration_status, identity_verification_status,
          device_enrollment_status, risk_status, risk_score, risk_reasons,
          review_required, created_at, updated_at
        ) VALUES (?, 'approved', 'verified', 'enrolled', 'ACTIVE', 5.0, '[]', 0, ?, ?)
        ON CONFLICT(user_id) DO UPDATE SET
          registration_status = 'approved',
          identity_verification_status = 'verified',
          device_enrollment_status = 'enrolled',
          risk_status = 'ACTIVE',
          risk_score = 5.0,
          risk_reasons = '[]',
          review_required = 0,
          updated_at = ?
      `).run(userId, now, now, now);
      console.log(`[Demo Seed] Updated existing demo driver profile: ${userId}`);
    } else {
      userId = `usr_demo_${crypto.randomUUID().slice(0, 8)}`;
      db.prepare(`
        INSERT INTO users (id, email, phone, password_hash, role, account_status, created_at, updated_at)
        VALUES (?, ?, ?, ?, 'driver', 'active', ?, ?)
      `).run(userId, normalizedEmail, phone, passwordHash, now, now);

      db.prepare(`
        INSERT INTO rider_profiles (
          user_id, registration_status, identity_verification_status,
          device_enrollment_status, risk_status, risk_score, risk_reasons,
          review_required, created_at, updated_at
        ) VALUES (?, 'approved', 'verified', 'enrolled', 'ACTIVE', 5.0, '[]', 0, ?, ?)
      `).run(userId, now, now);
      console.log(`[Demo Seed] Created new demo driver profile: ${userId}`);
    }

    // Ensure an enrolled and approved active device exists
    const deviceId = `dev_demo_${userId}`;
    db.prepare(`
      INSERT INTO devices (id, rider_id, platform, status, created_at, updated_at)
      VALUES (?, ?, 'android', 'active', ?, ?)
      ON CONFLICT(id) DO UPDATE SET status = 'active', updated_at = ?
    `).run(deviceId, userId, now, now, now);

    console.log('\n======================================================');
    console.log('  TRUST JUGGLER PRESENTATION DEMO USER READY');
    console.log('======================================================');
    console.log(`  Role               : Driver (Approved Account)`);
    console.log(`  Email              : ${normalizedEmail}`);
    console.log(`  Password           : ${password}`);
    console.log(`  Phone              : ${phone}`);
    console.log(`  Account Status     : active`);
    console.log(`  Registration Status: approved`);
    console.log(`  Identity Status    : verified`);
    console.log(`  Device Enrollment  : enrolled`);
    console.log(`  Risk Status        : ACTIVE (Score: 5.0)`);
    console.log('======================================================\n');
  } catch (error) {
    console.error('[Demo Seed] Error:', error);
    process.exit(1);
  } finally {
    closeDatabase();
  }
}

seedDemoUser();
