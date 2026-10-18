import { AuthService } from '../modules/auth/auth.service.js';
import { env } from '../config/env.js';
import { closeDatabase } from '../db/database.js';

async function run() {
  const email = process.env.ADMIN_EMAIL || process.argv.find(arg => arg.startsWith('email='))?.split('=')[1] || 'admin@trustjuggler.local';
  const password = process.env.ADMIN_PASSWORD || process.argv.find(arg => arg.startsWith('password='))?.split('=')[1] || 'AdminPass123!';

  console.log(`[Admin Bootstrap] Initializing admin account: ${email}`);

  try {
    const result = await AuthService.bootstrapAdmin({
      email,
      password,
      secret: env.ADMIN_BOOTSTRAP_SECRET,
    });

    console.log('[Admin Bootstrap] Success:', result);
  } catch (error) {
    console.error('[Admin Bootstrap] Error:', error);
    process.exit(1);
  } finally {
    closeDatabase();
  }
}

run();
